//
//  FrameData.swift
//  H264 Player
//
//  Created by AI Assistant on 2024/8/1.
//

import Foundation
import AVFoundation
import CoreMedia

struct FrameData: Identifiable {
    let id = UUID()
    let frameType: FrameType
    let size: Int
    let presentationTime: CMTime
    let image: CGImage?
    let index: Int
    let duration: CMTime
}

enum FrameType: String, CaseIterable {
    case IFrame = "I"
    case PFrame = "P"
    case BFrame = "B"
    case Unknown = "Unknown"
}

// 为 CMTime 创建一个包装器以支持 Identifiable
struct CMTimeWrapper: Identifiable {
    let time: CMTime
    var id: Int64 {
        return Int64(CMTimeGetSeconds(time).hashValue)
    }
    
    init(_ time: CMTime) {
        self.time = time
    }
}