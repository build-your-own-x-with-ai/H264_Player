//
//  ContentView.swift
//  H264 Player
//
//  Created by i on 2025/9/27.
//

import SwiftUI
import AVFoundation
import AppKit
import CoreMedia
import Combine

struct ContentView: View {
    @StateObject private var parser = H264Parser()
    @State private var selectedFileURL: URL?
    @State private var showFileImporter = false
    @State private var currentFrameInfo: String = ""
    @State private var securityScopedURL: URL?
    @State private var isAccessingFile = false
    
    var body: some View {
        VStack {
            // 顶部导航栏
            HStack {
                Text("H.264 播放器")
                    .font(.title)
                Spacer()
                Button("打开 H.264 文件") {
                    showFileImporter.toggle()
                }
                .padding(8)
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(4)
            }
            .padding()
            
            // 文件信息和内容区
            HStack(alignment: .top, spacing: 0) {
                // 侧边信息栏
                VStack(alignment: .leading, spacing: 15) {
                    if parser.isLoaded {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("文件信息:")
                                .font(.headline)
                            Text("\(selectedFileURL?.lastPathComponent ?? "无文件")")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Text("总帧数: \(parser.frames.count)")
                            Text("总时长: \(formatTime(parser.totalDuration))")
                        }
                    }
                    
                    Spacer()
                }
                .padding()
                .frame(minWidth: 200, maxWidth: 250)
                .background(Color.gray.opacity(0.1))
                
                // 主内容区
                VStack {
                    // 视频预览和控制
                    VStack {
                    // 视频预览区域
                    ZStack {
                        if let currentFrame = parser.frames.indices.contains(parser.currentFrameIndex) ? 
                           parser.frames[parser.currentFrameIndex].image : nil {
                            Image(currentFrame, scale: 1.0, orientation: .up, label: Text("当前帧"))
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: .infinity, maxHeight: 400)
                        } else {
                            Rectangle()
                                .fill(Color.gray)
                                .frame(maxWidth: .infinity, maxHeight: 400)
                                .overlay(Text("预览区域"))
                        }
                        
                        // 当前帧信息
                        if let frame = parser.frames.indices.contains(parser.currentFrameIndex) ? 
                           parser.frames[parser.currentFrameIndex] : nil {
                            VStack {
                                Spacer()
                                HStack {
                                    Text("帧 \(frame.index + 1)/\(parser.frames.count) | \(frame.frameType.rawValue)帧 | 大小: \(formatSize(frame.size))")
                                        .padding(8)
                                        .background(Color.black.opacity(0.7))
                                        .foregroundColor(.white)
                                        .font(.caption)
                                    Spacer()
                                }
                            }
                        }
                    }
                    
                    // 播放控制
                    HStack(spacing: 10) {
                        Button(action: parser.previousFrame) {
                            Image(systemName: "backward.frame")
                        }
                        .disabled(parser.frames.isEmpty || parser.currentFrameIndex <= 0)
                        
                        Button(action: {
                            if parser.isPlaying {
                                parser.pause()
                            } else {
                                parser.play()
                            }
                        }) {
                            Image(systemName: parser.isPlaying ? "pause.fill" : "play.fill")
                        }
                        .disabled(parser.frames.isEmpty)
                        
                        Button(action: parser.nextFrame) {
                            Image(systemName: "forward.frame")
                        }
                        .disabled(parser.frames.isEmpty || parser.currentFrameIndex >= parser.frames.count - 1)
                        
                        Spacer()
                    }
                    .padding()
                    
                    // 进度条
                    if !parser.frames.isEmpty {
                        HStack {
                            Text(formatTime(parser.frames[parser.currentFrameIndex].presentationTime))
                                .font(.caption)
                            Slider(value: Binding(
                                get: {
                                    Double(parser.currentFrameIndex) / Double(max(1, parser.frames.count - 1))
                                },
                                set: {
                                    let newIndex = Int($0 * Double(parser.frames.count - 1))
                                    parser.currentFrameIndex = newIndex
                                }
                            ))
                            Text(formatTime(parser.totalDuration))
                                .font(.caption)
                        }
                        .padding(.horizontal)
                    }
                }
                .background(Color.black.opacity(0.05))
                .cornerRadius(10)
                .padding()
                
                    // 帧数据图表
                    FrameChartView(
                        frames: parser.frames,
                        currentFrameIndex: parser.currentFrameIndex
                    )
                    .padding()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.movie, .data],
            allowsMultipleSelection: false
        ) { result in
            do {
                let selectedFiles = try result.get()
                if let url = selectedFiles.first {
                    // Create a bookmark first to ensure we can maintain access
                    do {
                        _ = try url.bookmarkData(options: .withSecurityScope,
                                               includingResourceValuesForKeys: nil,
                                               relativeTo: nil)
                        print("Successfully created bookmark for file")
                    } catch {
                        print("Warning: Failed to create bookmark: \(error)")
                    }
                    
                    // Handle security-scoped resource access
                    if url.startAccessingSecurityScopedResource() {
                        isAccessingFile = true
                        securityScopedURL = url
                        selectedFileURL = url
                        
                        // Parse the file with the security-scoped URL
                        // Since parseFile already handles background processing internally,
                        // we can call it directly from the main thread
                        parser.parseFile(url: url)
                        
                        // The security-scoped URL will be stopped in onDisappear or within parseFile
                        // depending on the implementation
                    } else {
                        print("Failed to gain access to the file: Operation not permitted")
                        // Try to use bookmark data if we have it
                        if let bookmarkData = try? url.bookmarkData(options: .withSecurityScope,
                                                                 includingResourceValuesForKeys: nil,
                                                                 relativeTo: nil) {
                            var isStale = false
                            do {
                                let bookmarkURL = try URL(resolvingBookmarkData: bookmarkData,
                                                         options: .withSecurityScope,
                                                         relativeTo: nil,
                                                         bookmarkDataIsStale: &isStale)
                                if bookmarkURL.startAccessingSecurityScopedResource() {
                                    DispatchQueue.main.async {
                                        self.isAccessingFile = true
                                        self.securityScopedURL = bookmarkURL
                                        self.selectedFileURL = bookmarkURL
                                        self.parser.parseFile(url: bookmarkURL)
                                    }
                                }
                            } catch {
                                print("Failed to resolve bookmark: \(error)")
                            }
                        }
                    }
                }
            } catch {
                print("Error selecting file: \(error)")
            }
        }
        .onDisappear {
            // Stop accessing the security-scoped resource when done
            if isAccessingFile, let url = securityScopedURL {
                url.stopAccessingSecurityScopedResource()
                isAccessingFile = false
                securityScopedURL = nil
            }
        }
        // Add an onReceive modifier to listen for parser.isLoaded to stop accessing when done
        .onReceive(Just(parser.isLoaded)) {
            if $0 && isAccessingFile, securityScopedURL != nil {
                // Optional: Stop accessing after parsing is complete
                // Uncomment this if you want to stop accessing immediately after parsing
                // self.securityScopedURL?.stopAccessingSecurityScopedResource()
                // self.isAccessingFile = false
                // self.securityScopedURL = nil
            }
        }
        .frame(minWidth: 800, minHeight: 600)
    }
    
    // 格式化时间
    private func formatTime(_ time: CMTime) -> String {
        let seconds = CMTimeGetSeconds(time)
        let minutes = Int(seconds / 60)
        let remainingSeconds = Int(seconds.truncatingRemainder(dividingBy: 60))
        let milliseconds = Int((seconds - Double(Int(seconds))) * 1000)
        return String(format: "%02d:%02d.%03d", minutes, remainingSeconds, milliseconds)
    }
    
    // 格式化文件大小
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

#Preview {
    ContentView()
}
