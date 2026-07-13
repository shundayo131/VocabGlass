//
//  CardAPI.swift
//  VocabGlass
//
//  Sends a captured photo to the worker and returns the generated card.
//

import Foundation
import UIKit

enum CardAPI {
    // The worker endpoint for card generation 
    static let endpoint = WorkerConfig.endpoint("generate")

    struct Payload: Encodable {
        let image: String       // base64 jpeg
        let mediaType: String
    }

    static func generate(from image: UIImage) async throws -> LearningCard {
        // Downscale before upload. Glasses photos are several MB; sending
        // them whole made card generation take 3 to 14 seconds depending
        // on the uplink (measured in M9). Identifying one object needs
        // far less than full resolution.
        let sized = image.resized(maxDimension: 1024)
        guard let jpeg = sized.jpegData(compressionQuality: 0.7) else {
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

private extension UIImage {
    // Scale down so the longest edge fits maxDimension; returns self if
    // the image is already small enough.
    func resized(maxDimension: CGFloat) -> UIImage {
        let longest = max(size.width, size.height)
        guard longest > maxDimension else { return self }
        let scale = maxDimension / longest
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: newSize, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
