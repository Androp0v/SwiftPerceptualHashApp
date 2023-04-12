//
//  ProcessImage.swift
//  SwiftPerceptualHashApp
//
//  Created by Raúl Montón Pinillos on 12/4/23.
//

import Foundation
import Metal
import MetalKit
import MetalPerformanceShaders
import UIKit

class PerceptualHash {
    
    let resizedSize: Int = 32
    let dctSize: Int = 8
    
    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    let grayscalePSO: MTLComputePipelineState
    
    let texture: MTLTexture
    let resizedTexture: MTLTexture
    let dctTexture: MTLTexture
    
    // MARK: - Initialization
    
    init?() {
        // Get the image
        let image = UIImage(named: "SampleImageFull.png")
        
        // Get the image data
        guard let imageData = image?.pngData() else {
            print("Failed to get image data!")
            return nil
        }
        
        // Get Metal device
        guard let device = MTLCreateSystemDefaultDevice() else {
            print("Metal device creation failed!")
            return nil
        }
        self.device = device
        
        // Get the default library
        guard let defaultLibrary = device.makeDefaultLibrary() else {
            print("Couldn't create default library!")
            return nil
        }
        
        // Create the grayscale kernel function
        guard let grayscaleKernel = defaultLibrary.makeFunction(name: "grayscale_kernel") else {
            print("Failed to create grayscale kernel!")
            return nil
        }
        
        // Create the grayscale Pipeline State Object
        guard let grayscalePSO = try? device.makeComputePipelineState(function: grayscaleKernel) else {
            print("Failed to create grayscale pipeline!")
            return nil
        }
        self.grayscalePSO = grayscalePSO
        
        // Create a texture loader
        let textureLoader = MTKTextureLoader(device: device)
        
        // Get texture from image
        guard let texture = try? textureLoader.newTexture(
            data: imageData,
            options: [
                MTKTextureLoader.Option.textureUsage: MTLTextureUsage.unknown.rawValue,
                MTKTextureLoader.Option.textureStorageMode: MTLStorageMode.shared.rawValue
            ]
        ) else {
            print("Failed to create texture from image data!")
            return nil
        }
        self.texture = texture
        
        // Create a 32x32 destination texture
        let resizedTextureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: resizedSize,
            height: resizedSize,
            mipmapped: false
        )
        resizedTextureDescriptor.usage = [.shaderRead, .shaderWrite]
        guard let resizedTexture = device.makeTexture(descriptor: resizedTextureDescriptor) else {
            print("Failed to create \(resizedSize)x\(resizedSize) destination texture.")
            return nil
        }
        self.resizedTexture = resizedTexture
        
        // Create a 8x8 destination texture to store the Discrete Cosine Transform
        let dctTextureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r32Float,
            width: dctSize,
            height: dctSize,
            mipmapped: false
        )
        dctTextureDescriptor.usage = [.shaderRead, .shaderWrite]
        guard let dctTexture = device.makeTexture(descriptor: dctTextureDescriptor) else {
            print("Failed to create \(dctSize)x\(dctSize) DCT texture.")
            return nil
        }
        self.dctTexture = dctTexture
        
        // Create command queue
        guard let commandQueue = device.makeCommandQueue() else {
            print("Failed to create command queue!")
            return nil
        }
        self.commandQueue = commandQueue
    }
    
    // MARK: - Can be reused
    
    func perceptualHash() async throws -> CGImage? {
            
        // Create command buffer
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            print("Failed to create command buffer!")
            return nil
        }
        
        // MARK: - Resize
        
        // Resize the image to target 32x32 resolution
        let resize = MPSImageBilinearScale(device: device)
        var transform = MPSScaleTransform(
            scaleX: Double(resizedSize) / Double(texture.width),
            scaleY: Double(resizedSize) / Double(texture.height),
            translateX: 0.0,
            translateY: 0.0
        )
        withUnsafePointer(to: &transform) { (transformPtr: UnsafePointer<MPSScaleTransform>) -> () in
            resize.scaleTransform = transformPtr
        }
        resize.encode(
            commandBuffer: commandBuffer,
            sourceTexture: texture,
            destinationTexture: resizedTexture
        )
        
        // MARK: - Grayscale
        
        // Create compute command encoder
        guard let computeEncoder = commandBuffer.makeComputeCommandEncoder() else {
            print("Failed to create compute command encoder!")
            return nil
        }
        
        // Set the PSO to perform a grayscale conversion
        computeEncoder.setComputePipelineState(grayscalePSO)
        
        // Set the source texture
        computeEncoder.setTexture(resizedTexture, index: 0)
        
        // Dispatch the threads
        let threadgroupSize = MTLSizeMake(16, 16, 1)
        var threadgroupCount = MTLSize()
        threadgroupCount.width  = (resizedTexture.width + threadgroupSize.width - 1) / threadgroupSize.width
        threadgroupCount.height = (resizedTexture.height + threadgroupSize.height - 1) / threadgroupSize.height
        // The image data is 2D, so set depth to 1
        threadgroupCount.depth = 1
        computeEncoder.dispatchThreadgroups(threadgroupCount, threadsPerThreadgroup: threadgroupSize)
        
        // Finish encoding
        computeEncoder.endEncoding()
        
        // MARK: - Finish
        
        let cgImage = await withCheckedContinuation { continuation in
            commandBuffer.addCompletedHandler { _ in
                continuation.resume(returning: self.resizedTexture.getCGImage())
            }
            
            // Submit work to the GPU
            commandBuffer.commit()
        }
        return cgImage
    }
}
