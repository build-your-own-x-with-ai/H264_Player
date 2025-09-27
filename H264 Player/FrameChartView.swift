//
//  FrameChartView.swift
//  H264 Player
//
//  Created by AI Assistant on 2024/8/1.
//

import SwiftUI
import CoreMedia

struct FrameChartView: View {
    let frames: [FrameData]
    let currentFrameIndex: Int
    
    var body: some View {
        VStack {
            Text("帧数据统计")
                .font(.headline)
                .padding(.bottom, 10)
            
            if frames.isEmpty {
                Text("没有帧数据可用")
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                // 帧类型分布（使用简单的条形图样式）
                VStack(alignment: .leading) {
                    Text("帧类型分布")
                        .font(.subheadline)
                        .padding(.bottom, 5)
                    
                    createFrameTypeBars()
                }
                .padding(.bottom, 20)
                
                // 帧大小信息
                VStack(alignment: .leading) {
                    Text("帧大小信息")
                        .font(.subheadline)
                        .padding(.bottom, 5)
                    
                    HStack {
                        Text("最小: \(formatSize(minFrameSize()))")
                        Spacer()
                        Text("平均: \(formatSize(avgFrameSize()))")
                        Spacer()
                        Text("最大: \(formatSize(maxFrameSize()))")
                    }
                }
                .padding(.bottom, 20)
                
                // 当前帧信息
                if let currentFrame = frames.indices.contains(currentFrameIndex) ? frames[currentFrameIndex] : nil {
                    VStack(alignment: .leading) {
                        Text("当前帧信息")
                            .font(.subheadline)
                            .padding(.bottom, 5)
                        
                        HStack {
                            Text("帧类型: \(currentFrame.frameType.rawValue)")
                            Spacer()
                            Text("大小: \(formatSize(currentFrame.size))")
                            Spacer()
                            Text("时间: \(formatTime(currentFrame.presentationTime))")
                        }
                    }
                    .padding(.bottom, 20)
                }
                
                // 统计信息
                HStack {
                    Text("总帧数: \(frames.count)")
                    Spacer()
                    Text("总时长: \(formatTime(frames.last?.presentationTime ?? .zero))")
                }
                .font(.footnote)
                .foregroundColor(.secondary)
                .padding()
            }
        }
    }
    
    // 创建帧类型分布的简化条形图
    private func createFrameTypeBars() -> some View {
        let iFrames = frames.filter { $0.frameType == .IFrame }.count
        let pFrames = frames.filter { $0.frameType == .PFrame }.count
        let bFrames = frames.filter { $0.frameType == .BFrame }.count
        let unknownFrames = frames.filter { $0.frameType == .Unknown }.count
        
        let total = frames.count
        
        return HStack(alignment: .bottom, spacing: 10) {
            createFrameTypeBar(value: iFrames, total: total, color: .red, label: "I 帧")
            createFrameTypeBar(value: pFrames, total: total, color: .green, label: "P 帧")
            createFrameTypeBar(value: bFrames, total: total, color: .blue, label: "B 帧")
            createFrameTypeBar(value: unknownFrames, total: total, color: .gray, label: "未知帧")
        }
        .frame(height: 100)
    }
    
    // 创建单个帧类型的条形
    private func createFrameTypeBar(value: Int, total: Int, color: Color, label: String) -> some View {
        let percentage = total > 0 ? Double(value) / Double(total) : 0
        
        return VStack {
            Rectangle()
                .fill(color)
                .frame(width: 40, height: percentage * 80)
                .cornerRadius(4)
            Text("\(value)")
                .font(.caption)
            Text(label)
                .font(.caption2)
        }
    }
    
    // 计算最小帧大小
    private func minFrameSize() -> Int {
        return frames.min { $0.size < $1.size }?.size ?? 0
    }
    
    // 计算平均帧大小
    private func avgFrameSize() -> Int {
        if frames.isEmpty { return 0 }
        return frames.reduce(0) { $0 + $1.size } / frames.count
    }
    
    // 计算最大帧大小
    private func maxFrameSize() -> Int {
        return frames.max { $0.size < $1.size }?.size ?? 0
    }
    
    private func formatTime(_ time: CMTime) -> String {
        let seconds = CMTimeGetSeconds(time)
        let minutes = Int(seconds / 60)
        let remainingSeconds = Int(seconds.truncatingRemainder(dividingBy: 60))
        return String(format: "%02d:%02d", minutes, remainingSeconds)
    }
    
    private func formatSize(_ bytes: Int) -> String {
        if bytes < 1024 {
            return "\(bytes) B"
        } else if bytes < 1024 * 1024 {
            return String(format: "%.2f KB", Double(bytes) / 1024.0)
        } else {
            return String(format: "%.2f MB", Double(bytes) / (1024.0 * 1024.0))
        }
    }
}