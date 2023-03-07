//
//  ViewController.swift
//  ImageConverter
//
//  Created by Ryan.Fan on 2023/3/7.
//

import Cocoa
import Foundation
import SDWebImage
import SnapKit

class ViewController: NSViewController {
    
    private lazy var titleLabel: NSTextField = {
        let textField = NSTextField(labelWithString: "请将图片或者文件夹拖拽至白框里")
        textField.font = .systemFont(ofSize: 18, weight: .bold)
        textField.textColor = .black
        return textField
    }()
    
    private lazy var destinationView: DestinationView = {
        let view = DestinationView()
        view.registerForDraggedTypes([NSPasteboard.PasteboardType.fileURL])
        return view
    }()
    
    override func viewDidLoad() {
        super.viewDidLoad()

        // Do any additional setup after loading the view.
        view.addSubview(titleLabel)
        titleLabel.snp.makeConstraints {
            $0.leading.trailing.equalToSuperview().inset(24)
            $0.top.equalToSuperview().inset(16)
        }
        
        view.addSubview(destinationView)
        destinationView.snp.makeConstraints {
            $0.leading.bottom.trailing.equalToSuperview()
            $0.top.equalTo(titleLabel.snp.bottom)
            $0.height.equalTo(destinationView.snp.width)
        }
    }

    override var representedObject: Any? {
        didSet {
        // Update the view, if already loaded.
        }
    }
}

private extension ViewController {
    
    final class DestinationView: NSView {
        override func draw(_ dirtyRect: NSRect) {
            super.draw(dirtyRect)
            
            guard let context = NSGraphicsContext.current?.cgContext else { return }
            
            // draw background and board
            context.saveGState()
            context.setFillColor(NSColor.white.cgColor)
            context.setStrokeColor(NSColor(hexString: "0xBFBFBF")!.cgColor)
            context.setLineWidth(1)
            context.setLineDash(phase: 0, lengths: [8, 2])
            let path = NSBezierPath(roundedRect: dirtyRect.insetBy(dx: 24, dy: 16), xRadius: 16, yRadius: 16)
            path.fill()
            path.stroke()
            context.restoreGState()
            
            // draw
        }
        
        override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
            .copy
        }
        
        override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
            let pasteBoard = sender.draggingPasteboard
            return pasteBoard.types?.contains(.fileURL) == true
        }
        
        override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
            let pasteBoard = sender.draggingPasteboard
            guard let fileURL = NSURL(from: pasteBoard) as? URL else {
                return false
            }
            
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: fileURL.path,
                                                 isDirectory: &isDir) else {
                return false
            }
            
            if isDir.boolValue {
                Task {
                    do {
                        let picFileURLs = try ImageHandler.findAllPics(from: fileURL)
                        guard !picFileURLs.isEmpty else {
                            showAlert(messageText: "该文件夹下没有图片文件"); return
                        }
                        try await ImageHandler.convertImages(from: picFileURLs, dirURL: fileURL)
                        showAlert(messageText: "完成了")
                    } catch let error where error is CancellationError {
                        // cancel
                    } catch {
                        showAlert(messageText: "转化图片失败，错误理由:\(error.localizedDescription)")
                    }
                }
                
                return true
            } else if ImageHandler.picExtensions.contains(fileURL.pathExtension) {
                Task {
                    do {
                        try await ImageHandler.convertImage(from: fileURL)
                        showAlert(messageText: "完成了")
                    } catch let error where error is CancellationError {
                        // cancel
                    } catch {
                        showAlert(messageText: "转化图片失败，错误理由:\(error.localizedDescription)")
                    }
                }
                return true
            } else {
                showAlert(messageText: "只支持转化\(ImageHandler.picExtensions.joined(separator: ","))三种类型的文件")
                return false
            }
        }
        
        private func showAlert(messageText: String) {
            let alert = NSAlert()
            alert.messageText = messageText
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }
}

extension NSColor {
    
    convenience init?(hexString: String) {
        let charactetSet = CharacterSet(charactersIn: "#")
        var hex = hexString.trimmingCharacters(in: charactetSet)
        let prefix = "0x"
        if hex.lowercased().hasPrefix(prefix) {
            hex = hex.replacingOccurrences(of: prefix, with: "")
        }

        if hex.count == 6 {
            hex = "FF\(hex)"
        } else if hex.count == 2 {
            hex = "FF\(hex)\(hex)\(hex)"
        }

        if let value = Int(hex, radix: 16), [2, 6, 8].contains(hex.count) {
            self.init(red: CGFloat((value & 0xFF0000) >> 16) / 255.0,
                      green: CGFloat((value & 0xFF00) >> 8) / 255.0,
                      blue: CGFloat(value & 0xFF) / 255.0,
                      alpha: CGFloat((value & 0xFF000000) >> 24) / 255.0)
        } else {
            assertionFailure("[UIColor] Failed to create an integer from hex string.")
            self.init(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.0) // A fallback transparent white color
        }
    }
}
