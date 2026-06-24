//
//  CardAPI.swift
//  VocabGlass
//
//  Sends a captured photo to the worker and returns the generated card.
//

import Foundation
import UIKit

enum CardAPI {
    // Simulator can reach the Mac's localhost. For a real device, point this at
    // the deployed worker URL instead.
    static let endpoint = URL(string: "http://localhost:8787/generate")!

    struct Payload: Encodable {
        let image: String       // base64 jpeg
        let mediaType: String
    }

    static func generate(from image: UIImage) async throws -> LearningCard {
        guard let jpeg = image.jpegData(compressionQuality: 0.8) else {
            throw URLError(.cannotDecodeContentData)
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            Payload(image: jpeg.base64EncodedString(), mediaType: "image/jpeg")
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            // Surface the worker's error body to make failures readable.
            let body = String(data: data, encoding: .utf8) ?? "unknown error"
            throw NSError(domain: "CardAPI", code: 1, userInfo: [NSLocalizedDescriptionKey: body])
        }

        return try JSONDecoder().decode(LearningCard.self, from: data)
    }
}
