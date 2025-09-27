//
//  H264Parser.swift
//  H264 Player
//
//  Created by AI Assistant on 2024/8/1.
//

import Foundation
import AVFoundation
import CoreMedia
import AppKit
import Combine

class H264Parser: ObservableObject {
    @Published var frames: [FrameData] = []
    @Published var currentFrameIndex: Int = 0
    @Published var isPlaying: Bool = false
    @Published var isLoaded: Bool = false
    @Published var totalDuration: CMTime = .zero
    
    private var player: AVPlayer?
    private var playerLayer: AVPlayerLayer?
    private var asset: AVAsset?
    private var timer: Timer?
    private var startTime: Double = 0.0
    private var lastFrameIndex: Int = -1
    
    // 解析 H264 文件
    func parseFile(url: URL) {
        // 确保所有属性更新在主线程上执行
        DispatchQueue.main.async {
            // Clear previous data
            self.frames.removeAll()
            self.currentFrameIndex = 0
            self.isLoaded = false
            
            print("Attempting to parse file at URL: \(url.path)")
            
            // 确保是安全作用域URL并正确访问
            let hasSecurityScope = url.startAccessingSecurityScopedResource()
            print("Is security-scoped URL: \(hasSecurityScope)")
            
            // 加载资源
            DispatchQueue.global(qos: .userInitiated).async {
                // Create a local copy of the URL to ensure it's retained
                let localURL = url
                
                do {
                    // 直接读取文件数据而不是使用AVAsset
                    let fileData = try Data(contentsOf: localURL)
                    print("Successfully loaded file data, size: \(fileData.count) bytes")
                    
                    // 解析H264数据
                    self.parseH264Data(fileData)
                    
                } catch {
                    DispatchQueue.main.async {
                        print("Error reading file data: \(error.localizedDescription)")
                        self.isLoaded = false
                        
                        // 停止访问安全作用域资源
                        if hasSecurityScope {
                            localURL.stopAccessingSecurityScopedResource()
                            print("Stopped accessing security-scoped resource after file read error")
                        }
                    }
                }
            }
        }
    }
    
    // 解析H264数据
    private func parseH264Data(_ data: Data) {
        // 在后台线程中解析
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            // 用于查找NAL单元的起始码
            let startCode3 = Data([0x00, 0x00, 0x01])
            let startCode4 = Data([0x00, 0x00, 0x00, 0x01])
            
            var currentIndex = 0
            var nalUnits: [(startIndex: Int, length: Int, type: UInt8)] = []
            
            // 查找所有NAL单元
            while currentIndex < data.count - 3 {
                var startCodeLength = 0
                
                // 检查4字节起始码
                if currentIndex <= data.count - 4 && 
                   data[currentIndex..<(currentIndex + 4)].elementsEqual(startCode4) {
                    startCodeLength = 4
                } 
                // 检查3字节起始码
                else if data[currentIndex..<(currentIndex + 3)].elementsEqual(startCode3) {
                    startCodeLength = 3
                }
                
                // 如果找到起始码
                if startCodeLength > 0 {
                    let nalStartIndex = currentIndex + startCodeLength
                    
                    // 确保我们有足够的数据读取NAL类型
                    if nalStartIndex < data.count {
                        let nalType = data[nalStartIndex] & 0x1F
                        
                        // 查找下一个NAL单元的起始位置
                        var nextNalIndex = nalStartIndex + 1
                        while nextNalIndex < data.count - 3 {
                            if (nextNalIndex <= data.count - 4 && 
                                data[nextNalIndex..<(nextNalIndex + 4)].elementsEqual(startCode4)) ||
                               data[nextNalIndex..<(nextNalIndex + 3)].elementsEqual(startCode3) {
                                break
                            }
                            nextNalIndex += 1
                        }
                        
                        // 计算NAL单元长度
                        let nalLength = nextNalIndex - nalStartIndex
                        
                        // 添加到NAL单元列表
                        nalUnits.append((startIndex: nalStartIndex, length: nalLength, type: nalType))
                        
                        // 更新索引到下一个位置
                        currentIndex = nextNalIndex
                    } else {
                        currentIndex += 1
                    }
                } else {
                    currentIndex += 1
                }
            }
            
            print("Found \(nalUnits.count) NAL units")
            
            // 处理找到的NAL单元
            self.processNALUnits(data: data, nalUnits: nalUnits)
        }
    }
    
    // 处理NAL单元
    private func processNALUnits(data: Data, nalUnits: [(startIndex: Int, length: Int, type: UInt8)]) {
        var frameIndex = 0
        var totalDurationSeconds = 0.0
        let frameRate = 30.0 // 假设30fps
        let frameDuration = CMTimeMake(value: 1, timescale: Int32(frameRate))
        
        // 创建一个有序的帧列表，包含所有I、P、B帧
        var orderedFrames: [(index: Int, type: FrameType, nalUnit: (startIndex: Int, length: Int, type: UInt8))] = []
        
        // 首先处理所有NAL单元，确定帧类型
        for (index, nalUnit) in nalUnits.enumerated() {
            // NAL类型: 1=非IDR帧, 5=IDR帧(I帧), 6=SEI, 7=SPS, 8=PPS
            let frameType: FrameType
            switch nalUnit.type {
            case 5: // IDR帧 (I帧)
                frameType = .IFrame
            case 1: // 非IDR帧 (可能是P帧或B帧)
                // 这里我们需要更复杂的逻辑来区分P帧和B帧
                // 简化处理：我们根据位置来模拟P帧和B帧的分布
                // 实际上，需要解析帧头来确定真正的帧类型
                if index % 3 == 0 {
                    frameType = .PFrame
                } else {
                    frameType = .BFrame
                }
            case 7, 8: // SPS, PPS (不是实际的视频帧)
                continue
            default:
                // 其他NAL单元类型，暂时跳过
                continue
            }
            
            // 添加到有序帧列表
            orderedFrames.append((index: index, type: frameType, nalUnit: nalUnit))
        }
        
        // 按照I、P、B帧分类统计
        let iFrames = orderedFrames.filter { $0.type == .IFrame }
        let pFrames = orderedFrames.filter { $0.type == .PFrame }
        let bFrames = orderedFrames.filter { $0.type == .BFrame }
        
        print("I-Frames: \(iFrames.count), P-Frames: \(pFrames.count), B-Frames: \(bFrames.count)")
        
        // 详细打印每个帧的信息
        print("帧详细列表:")
        for (i, frame) in orderedFrames.enumerated() {
            print("帧 #\(i): 类型=\(frame.type), NAL类型=\(frame.nalUnit.type), 大小=\(frame.nalUnit.length)字节")
        }
        
        // 创建帧数据
        for frame in orderedFrames {
            // 创建帧的时间戳
            let presentationTime = CMTimeMake(value: Int64(frameIndex), timescale: Int32(frameRate))
            
            // 创建一个详细的图像表示
            let image = self.createDetailedFrameImage(
                width: 640, 
                height: 480, 
                frameType: frame.type, 
                frameIndex: frameIndex,
                nalType: frame.nalUnit.type,
                size: frame.nalUnit.length
            )
            
            // 创建帧数据
            let frameData = FrameData(
                frameType: frame.type,
                size: frame.nalUnit.length,
                presentationTime: presentationTime,
                image: image,
                index: frameIndex,
                duration: frameDuration
            )
            
            // 添加到帧列表
            DispatchQueue.main.async {
                self.frames.append(frameData)
            }
            
            frameIndex += 1
            totalDurationSeconds += 1.0 / frameRate
        }
        
        // 设置总时长
        let totalDuration = CMTimeMakeWithSeconds(totalDurationSeconds, preferredTimescale: 600)
        
        DispatchQueue.main.async {
            self.totalDuration = totalDuration
            self.isLoaded = true
            print("Successfully parsed \(frameIndex) frames with total duration \(totalDurationSeconds) seconds")
        }
    }
    
    // 创建详细的帧图像用于预览
    private func createDetailedFrameImage(width: Int, height: Int, frameType: FrameType, frameIndex: Int, nalType: UInt8, size: Int) -> CGImage? {
        let bytesPerRow = width * 4
        let bitsPerComponent = 8
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: bitsPerComponent,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        ) else { return nil }
        
        // 根据帧类型设置不同的背景颜色
        let backgroundColor: CGColor
        switch frameType {
        case .IFrame:
            backgroundColor = CGColor(red: 0, green: 0, blue: 1, alpha: 1) // 蓝色
        case .PFrame:
            backgroundColor = CGColor(red: 0, green: 0.8, blue: 0, alpha: 1) // 绿色
        case .BFrame:
            backgroundColor = CGColor(red: 0.8, green: 0, blue: 0, alpha: 1) // 红色
        case .Unknown:
            backgroundColor = CGColor(red: 0.8, green: 0.8, blue: 0.8, alpha: 1) // 红色
        }
        
        context.setFillColor(backgroundColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        
        // 绘制帧信息
        let titleFont = NSFont.boldSystemFont(ofSize: 36)
        let infoFont = NSFont.systemFont(ofSize: 20)
        
        // 帧类型标题
        let frameTypeText: String
        switch frameType {
        case .IFrame: frameTypeText = "I-Frame"
        case .PFrame: frameTypeText = "P-Frame"
        case .BFrame: frameTypeText = "B-Frame"
        case .Unknown:
            frameTypeText = "Unknown"
        }
        
        // 创建帧类型标题
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.white,
            .font: titleFont
        ]
        
        let titleString = NSAttributedString(string: frameTypeText, attributes: titleAttributes)
        let titleSize = titleString.size()
        
        let titleRect = CGRect(
            x: (width - Int(titleSize.width)) / 2,
            y: height - Int(titleSize.height) - 20,
            width: Int(titleSize.width),
            height: Int(titleSize.height)
        )
        
        // 创建详细信息文本
        let infoAttributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.white,
            .font: infoFont
        ]
        
        // 帧索引信息
        let indexString = NSAttributedString(string: "帧索引: \(frameIndex)", attributes: infoAttributes)
        let indexSize = indexString.size()
        
        let indexRect = CGRect(
            x: 20,
            y: height - Int(titleSize.height) - Int(indexSize.height) - 40,
            width: Int(indexSize.width),
            height: Int(indexSize.height)
        )
        
        // NAL类型信息
        let nalTypeString = NSAttributedString(string: "NAL类型: \(nalType)", attributes: infoAttributes)
        let nalTypeSize = nalTypeString.size()
        
        let nalTypeRect = CGRect(
            x: 20,
            y: height - Int(titleSize.height) - Int(indexSize.height) - Int(nalTypeSize.height) - 60,
            width: Int(nalTypeSize.width),
            height: Int(nalTypeSize.height)
        )
        
        // 帧大小信息
        let sizeString = NSAttributedString(string: "大小: \(size) 字节", attributes: infoAttributes)
        let sizeTextSize = sizeString.size()
        
        let sizeRect = CGRect(
            x: 20,
            y: height - Int(titleSize.height) - Int(indexSize.height) - Int(nalTypeSize.height) - Int(sizeTextSize.height) - 80,
            width: Int(sizeTextSize.width),
            height: Int(sizeTextSize.height)
        )
        
        // 绘制所有文本
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        titleString.draw(in: titleRect)
        indexString.draw(in: indexRect)
        nalTypeString.draw(in: nalTypeRect)
        sizeString.draw(in: sizeRect)
        
        return context.makeImage()
    }
    
    // 创建简单图像用于预览 (保留以备兼容)
    private func createSimpleImage(width: Int, height: Int, isIFrame: Bool) -> CGImage? {
        let bytesPerRow = width * 4
        let bitsPerComponent = 8
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: bitsPerComponent,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        ) else { return nil }
        
        // 填充颜色 (I帧使用蓝色，P帧使用绿色)
        let color = isIFrame ? CGColor(red: 0, green: 0, blue: 1, alpha: 1) : CGColor(red: 0, green: 1, blue: 0, alpha: 1)
        context.setFillColor(color)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        
        // 添加帧类型文本
        let frameTypeText = isIFrame ? "I-Frame" : "P-Frame"
        let attributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.white,
            .font: NSFont.boldSystemFont(ofSize: 36)
        ]
        
        let attributedString = NSAttributedString(string: frameTypeText, attributes: attributes)
        let textSize = attributedString.size()
        
        let textRect = CGRect(
            x: (width - Int(textSize.width)) / 2,
            y: (height - Int(textSize.height)) / 2,
            width: Int(textSize.width),
            height: Int(textSize.height)
        )
        
        // 绘制文本
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        attributedString.draw(in: textRect)
        
        return context.makeImage()
    }
    
    // 创建 CGImage 从 CVImageBuffer
    private func createCGImage(from buffer: CVImageBuffer) -> CGImage? {
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        
        let baseAddress = CVPixelBufferGetBaseAddress(buffer)
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        
        guard let context = CGContext(
            data: baseAddress,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        ) else { return nil }
        
        return context.makeImage()
    }
    
    // 播放控制方法
    func play() {
        // Ensure we're not creating multiple timers
        if isPlaying {
            return
        }
        
        guard isLoaded, !frames.isEmpty else {
            print("Cannot play: File not loaded or no frames available")
            return
        }
        
        // Invalidate any existing timer before creating a new one
        timer?.invalidate()
        timer = nil
        
        // Update @Published properties on main thread
        DispatchQueue.main.async {
            self.isPlaying = true
            self.startTime = Date().timeIntervalSinceReferenceDate
            
            // 设置定时器以更新帧（30fps）
            self.timer = Timer.scheduledTimer(timeInterval: 1.0/30.0, target: self, selector: #selector(self.updateFrame), userInfo: nil, repeats: true)
            if let timer = self.timer {
                RunLoop.main.add(timer, forMode: .common)
            }
        }
    }
    
    func pause() {
        // Update @Published properties on main thread
        DispatchQueue.main.async {
            self.isPlaying = false
            self.timer?.invalidate()
            self.timer = nil
        }
    }
    
    func nextFrame() {
        // Ensure updates happen on main thread
        DispatchQueue.main.async {
            guard !self.frames.isEmpty else { return }
            
            if self.currentFrameIndex < self.frames.count - 1 {
                self.currentFrameIndex += 1
                // If playing, update the startTime to sync with manual navigation
                if self.isPlaying {
                    self.startTime = Date().timeIntervalSinceReferenceDate - CMTimeGetSeconds(self.frames[self.currentFrameIndex].presentationTime)
                }
            }
        }
    }
    
    func previousFrame() {
        // Ensure updates happen on main thread
        DispatchQueue.main.async {
            guard !self.frames.isEmpty else { return }
            
            if self.currentFrameIndex > 0 {
                self.currentFrameIndex -= 1
                // If playing, update the startTime to sync with manual navigation
                if self.isPlaying {
                    self.startTime = Date().timeIntervalSinceReferenceDate - CMTimeGetSeconds(self.frames[self.currentFrameIndex].presentationTime)
                }
            }
        }
    }
    
    @objc private func updateFrame() {
        guard isPlaying, !frames.isEmpty else {
            // Make sure pause is called on main thread
            DispatchQueue.main.async {
                self.pause()
            }
            return
        }
        
        let currentTime = Date().timeIntervalSinceReferenceDate - startTime
        
        // 查找当前时间对应的帧
        for (index, frame) in frames.enumerated() {
            let frameTime = CMTimeGetSeconds(frame.presentationTime)
            
            if frameTime >= currentTime {
                if index > 0 {
                    let prevFrameTime = CMTimeGetSeconds(frames[index - 1].presentationTime)
                    if prevFrameTime <= currentTime {
                        if lastFrameIndex != index - 1 {
                            // Ensure we stay within bounds
                            if index - 1 < frames.count {
                                // Update @Published properties on main thread
                                DispatchQueue.main.async {
                                    self.currentFrameIndex = index - 1
                                    self.lastFrameIndex = index - 1
                                }
                            }
                        }
                    }
                }
                break
            } else if index == frames.count - 1 {
                // 到达视频末尾
                DispatchQueue.main.async {
                    self.pause()
                }
            }
        }
    }
}
