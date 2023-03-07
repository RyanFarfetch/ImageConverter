//
//  ImageHandler.swift
//  ImageConverter
//
//  Created by Ryan.Fan on 2023/3/7.
//

import Cocoa
import Foundation

@MainActor final class ImageHandler {
    
    enum Error: Swift.Error {
        case noImage
        case unsuitedRatio
        case compressFailure
    }
    
    private enum Constants {
        static let maxImageByte = 5 * 1024 * 1024
        static let maxPixelSize: CGFloat = 2000
        static let maxRatio: CGFloat = 10
    }
    
    static func findAllPics(from dirURL: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(atPath: dirURL.path).flatMap { fileName -> [URL] in
            let fileURL = dirURL.appendingPathComponent(fileName)
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDir) else {
                return []
            }
            
            if isDir.boolValue {
                return try findAllPics(from: fileURL)
            } else if Self.picExtensions.contains(fileURL.pathExtension) {
                return [fileURL]
            } else {
                return []
            }
        }
    }
    
    static func convertImages(from fileURLs: [URL], dirURL: URL) async throws {
        let openPanel = NSOpenPanel()
        openPanel.canChooseFiles = false
        openPanel.canCreateDirectories = true
        openPanel.canChooseDirectories = true
        openPanel.allowsMultipleSelection = false
        
        guard await openPanel.begin() == .OK, let outDirURL = openPanel.url else {
            throw CancellationError()
        }
        
        let fullRegex = try NSRegularExpression(pattern: #"^.*\(([1-9][0-9]*)\)"#)
        let numberRegex = try NSRegularExpression(pattern: #"\(([1-9][0-9]*)\)"#)
        await withThrowingTaskGroup(of: Void.self) { group in
            for fileURL in fileURLs {
                group.addTask {
                    // handle file path
                    let fileExtension = fileURL.pathExtension
                    var fileName = fileURL.deletingPathExtension().lastPathComponent
                    var targetURL = outDirURL.appendingPathComponent(fileName).appendingPathExtension(fileExtension)
                    while FileManager.default.fileExists(atPath: targetURL.path) {
                        guard fullRegex.matches(in: fileName, range: NSRange(fileName.startIndex..., in: fileName)).count > 0,
                              let lastMatched = numberRegex.matches(in: fileName, range: NSRange(fileName.startIndex..., in: fileName)).last else {
                            fileName += "(1)"
                            targetURL = outDirURL.appendingPathComponent(fileName).appendingPathExtension(fileExtension)
                            continue
                        }
                        let numberString = (fileName as NSString).substring(with: lastMatched.range).replacingOccurrences(of: "(", with: "").replacingOccurrences(of: ")", with: "")
                        guard let number = Int(numberString) else {
                            fileName += "(1)"
                            targetURL = outDirURL.appendingPathComponent(fileName).appendingPathExtension(fileExtension)
                            continue
                        }
                        
                        let targetSuffix = "(\(number + 1))"
                        fileName = (fileName as NSString).replacingCharacters(in: lastMatched.range, with: targetSuffix)
                        targetURL = outDirURL.appendingPathComponent(fileName).appendingPathExtension(fileExtension)
                    }
                    
                    // convert image
                    guard let image = NSImage(contentsOf: fileURL) else {
                        throw Error.noImage
                    }
                    
                    let imageData = try await compressToData(for: image)
                    try imageData.write(to: targetURL)
                }
            }
        }
    }
    
    static func convertImage(from fileURL: URL) async throws {
        let savePanel = NSSavePanel()
        savePanel.canCreateDirectories = true
        savePanel.showsTagField = false
        savePanel.nameFieldStringValue = fileURL.lastPathComponent
        savePanel.level = .modalPanel
        guard await savePanel.begin() == .OK, let url = savePanel.url else {
            throw CancellationError()
        }
        
        guard let image = NSImage(contentsOf: fileURL) else {
            throw Error.noImage
        }
        
        let imageData = try await compressToData(for: image)
        try imageData.write(to: url)
    }
    
    static func compressToData(for image: NSImage) async throws -> Data {
        try await Task<Data, Swift.Error>.detached(priority: .medium) {
            guard image.size.width > 0, image.size.height > 0,
                  image.size.height / image.size.width < Constants.maxRatio,
                  image.size.width / image.size.height < Constants.maxRatio else {
                throw Error.unsuitedRatio
            }
            
            // check pixel size
            // TODO: - Update image size
            let maxPixelSizeWithScale = Constants.maxPixelSize / image.scale
            var outputImage = image
            let maxRate = max(image.size.width / maxPixelSizeWithScale, image.size.height / maxPixelSizeWithScale)
            if maxRate > 1.0 {
                guard let _outputImage = image.sd_resizedImage(with: CGSize(width: image.size.width / maxRate, height: image.size.height / maxRate), scaleMode: .fill) else {
                    throw Error.compressFailure
                }
                
                outputImage = _outputImage
            }
            
            // check data size
            var quality: CGFloat = 0.9
            while let data = outputImage.jpegData(compressionQuality: quality), quality > 0 {
                if data.count <= Constants.maxImageByte {
                    print("## quality is \(quality)")
                    return data
                }
                quality -= 0.1
            }
            
            throw Error.compressFailure
        }.value
    }
    
    static let picExtensions: Set<String> = ["png", "jpeg", "jpg"]
}

extension NSImage {
    
    func jpegData(compressionQuality quality: Double) -> Data? {
        NSBitmapImageRep.representationOfImageReps(in: representations,
                                                   using: .jpeg,
                                                   properties: [.compressionFactor: NSDecimalNumber(floatLiteral: quality)])
    }
}
