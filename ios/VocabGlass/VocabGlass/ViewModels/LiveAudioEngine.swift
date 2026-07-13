//
//  LiveAudioEngine.swift
//  VocabGlass
//
//  Moves audio between the device microphone and a Gemini Live session:
//  taps the mic and emits 16 kHz PCM16 mono chunks, and plays back the
//  24 kHz PCM16 chunks Gemini sends. Knows nothing about WebSockets.
//
//  Not @MainActor: the mic tap runs on a realtime audio thread, so the
//  consumer hops to the main actor before touching UI or the socket.
//

import Foundation 
import AVFoundation 

final class LiveAudioEngine {

    // Callback invoked when a chunk of mic audio is ready to send.
    // Audio format: 16 kHz, PCM16, mono.
    var onMicChunk: ((Data) -> Void)? 

    private(set) var isRunning = false

    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private var inputConverter: AVAudioConverter?
    private var chunkCount = 0

    // Debug instrumentation (M13: remove): speech edge detection for the
    // session log. Peaks above the threshold mean the wearer is talking.
    // Audio-thread only.
    private var isSpeaking = false
    private var silentChunks = 0
    private let speechThreshold: Int16 = 500

    // Observability: seconds of reply audio scheduled but not yet
    // played, reported as playback backlog. Mutated on the main thread
    // only (play, flush, and the hop in the completion).
    private var queuedSeconds: Double = 0
    private var loggedQueueHighWater: Double = 0
    
    // What Gemini expects from us 
    private let sendFormat = AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: 16_000,
        channels: 1,
        interleaved: true
    )!

    // What Gemini sends back as floats for the mixer 
    private let playFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 24_000,
        channels: 1,
        interleaved: false
    )!

    // MARK: - Lifecycle 
    func start() throws {
        guard !isRunning else { return }

        engine.attach(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: playFormat)

        let input = engine.inputNode
        let micFormat = input.outputFormat(forBus: 0)
        // A dead audio device (broken simulator audio, missing mic)
        // reports a 0 Hz format; installTap would crash the app on it.
        guard micFormat.sampleRate > 0, micFormat.channelCount > 0 else {
            throw NSError(domain: "LiveAudioEngine", code: 1,
                          userInfo: [NSLocalizedDescriptionKey:
                            "no usable microphone input (broken audio device?)"])
        }
        inputConverter = AVAudioConverter(from: micFormat, to: sendFormat)

        // Roughly 100ms of audio per callback: low latency 
        // without spamming the socket with tiny messages
        input.installTap(onBus: 0, bufferSize: 4096, format: micFormat) {
            [weak self] buffer, _ in self?.convertAndForward(buffer)
        }

        try engine.start()
        playerNode.play()
        isRunning = true
    }

    func stop() {
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        playerNode.stop()
        engine.stop()
        isRunning = false
    }

    // MARK: - Mic -> Gemini 

    // Runs on the audio thread. Resample the mic buffer to 16 kHz Int16
    // and hand the raw bytes to the consumer
    private func convertAndForward(_ buffer: AVAudioPCMBuffer) {
        guard let converter = inputConverter else { return }

        let ratio = sendFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 16 
        guard let out = AVAudioPCMBuffer(pcmFormat: sendFormat, frameCapacity: capacity) else { return }

        // The converter pulls input through this closure; feed it our one buffer,
        // then report that no more data is coming for this call 
        var fed = false 
        converter.convert(to: out, error: nil) { _, outStatus in
            if fed {
                outStatus.pointee = .noDataNow
                return nil
            }
            fed = true
            outStatus.pointee = .haveData
            return buffer
        }

        guard out.frameLength > 0, let channel = out.int16ChannelData else { return }
        let data = Data(
            bytes: channel[0],
            count: Int(out.frameLength) * MemoryLayout<Int16>.size
        )
        // Debug instrumentation (M13: remove): speech edges for the
        // session log, when the wearer starts talking and when they stop
        // (about 1 s of quiet ends a turn).
        var peak: Int16 = 0
        for i in 0..<Int(out.frameLength) { peak = max(peak, abs(channel[0][i])) }
        if peak >= speechThreshold {
            silentChunks = 0
            if !isSpeaking {
                isSpeaking = true
                Diag.debug("mic", "speech start (peak \(peak))")
            }
        } else if isSpeaking {
            silentChunks += 1
            if silentChunks >= 4 {
                isSpeaking = false
                Diag.debug("mic", "speech end")
            }
        }

        #if DEBUG
        chunkCount += 1
        if chunkCount % 20 == 1 {
            print("mic chunk #\(chunkCount): \(data.count) bytes, peak \(peak)")
        }
        #endif
        onMicChunk?(data)
    }

    // MARK: - Gemini -> speaker

    // Throw away everything still queued for playback. Called when the
    // user talks over the model (Gemini sends "interrupted"): without
    // this the stale audio keeps playing, the queue outgrows realtime,
    // and the conversation drifts minutes behind.
    func flushPlayback() {
        Diag.event("play", String(format: "flush, discarded %.1f s", queuedSeconds))
        playerNode.stop()   // discards all scheduled buffers
        playerNode.play()   // ready for the next reply
        queuedSeconds = 0
        loggedQueueHighWater = 0
    }

    // Queue a 24 kHz PCM16 chunk for playback.
    // Chunks arrive faster than real time;
    // the player node plays them back to back in order
    func play(_ pcm: Data) {
        let frames = AVAudioFrameCount(pcm.count / MemoryLayout<Int16>.size)
        guard frames > 0,
            let buffer = AVAudioPCMBuffer(pcmFormat: playFormat, frameCapacity: frames) else { return }
        buffer.frameLength = frames

        pcm.withUnsafeBytes { raw in
            let int16 = raw.bindMemory(to: Int16.self)
            let out = buffer.floatChannelData![0]
            for i in 0..<Int(frames) {
                out[i] = Float(int16[i]) / 32768.0
            }
        }

        // Observability: track how far playback runs behind. Schedule
        // adds, the completion (hopped to main, where play() also runs)
        // subtracts. The log line only fires on a new backlog high.
        let seconds = Double(frames) / playFormat.sampleRate
        queuedSeconds += seconds
        if queuedSeconds > loggedQueueHighWater + 1 {
            loggedQueueHighWater = queuedSeconds
            Diag.event("play", String(format: "queue backlog %.1f s", queuedSeconds))
        }
        playerNode.scheduleBuffer(buffer) { [weak self] in
            DispatchQueue.main.async {
                self?.queuedSeconds = max(0, (self?.queuedSeconds ?? 0) - seconds)
            }
        }
    }
}