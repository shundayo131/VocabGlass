//
//  WorkerConfig.swift
//  VocabGlass
//
//  Resolves the worker base URL from the gitignored WorkerConfig.plist.
//  WorkerURL holds the base only (no path), e.g. https://xxx.workers.dev
//

import Foundation 

enum WorkerConfig {
    static let baseURL: URL = {
        if let url = Bundle.main.url(forResource: "WorkerConfig", withExtension: "plist"),
           let config = NSDictionary(contentsOf: url),
           let base = config["WorkerURL"] as? String,
           let parsed = URL(string: base) {
            return parsed
        }
        return URL(string: "http://localhost:8787")!   // wrangler dev
    }()

    static func endpoint(_ path: String) -> URL {
        baseURL.appendingPathComponent(path)
    }
}