import Cocoa
import Metal
import QuartzCore
import simd

extension float4x4 {
    static func perspective(fovY: Float, aspect: Float, near: Float, far: Float)
        -> float4x4
    {
        let yScale = 1 / tan(fovY * 0.5)
        let xScale = yScale / aspect
        let zRange = far - near
        let zScale = -(far + near) / zRange
        let wzScale = -2 * far * near / zRange

        return float4x4(
            columns: (
                SIMD4<Float>(xScale, 0, 0, 0),
                SIMD4<Float>(0, yScale, 0, 0),
                SIMD4<Float>(0, 0, zScale, -1),
                SIMD4<Float>(0, 0, wzScale, 0)
            )
        )
    }

    static func translation(_ t: SIMD3<Float>) -> float4x4 {
        float4x4(
            columns: (
                SIMD4<Float>(1, 0, 0, 0),
                SIMD4<Float>(0, 1, 0, 0),
                SIMD4<Float>(0, 0, 1, 0),
                SIMD4<Float>(t.x, t.y, t.z, 1)
            )
        )
    }

    static func rotationX(_ angle: Float) -> float4x4 {
        float4x4(
            columns: (
                [1, 0, 0, 0],
                [0, cos(angle), sin(angle), 0],
                [0, -sin(angle), cos(angle), 0],
                [0, 0, 0, 1]
            )
        )
    }

    static func rotationY(_ angle: Float) -> float4x4 {
        float4x4(
            columns: (
                [cos(angle), 0, sin(angle), 0],
                [0, 1, 0, 0],
                [-sin(angle), 0, cos(angle), 0],
                [0, 0, 0, 1]
            )
        )
    }

    static func rotationZ(_ angle: Float) -> float4x4 {
        float4x4(
            columns: (
                [cos(angle), sin(angle), 0, 0],
                [-sin(angle), cos(angle), 0, 0],
                [0, 0, 1, 0],
                [0, 0, 0, 1]
            )
        )
    }
}

struct CubeData {
    var transform: float4x4
    var color: SIMD4<Float>
}

class Cube {
    private var rotationAngle: Float = 0
    private var position: SIMD4<Float> = .zero
    private var color: SIMD4<Float>

    public init(position: SIMD4<Float>, color: SIMD4<Float>) {
        self.position = position
        self.color = color
    }

    public func updateTransform(aspect: Float) -> CubeData {
        rotationAngle += 0.01
        let projection = float4x4.perspective(
            fovY: .pi / 6,
            aspect: aspect,
            near: 0.1,
            far: 100
        )
        let view = float4x4.translation([0, 0, -2])
        let scale = float4x4(diagonal: SIMD4<Float>(0.1, 0.1, 0.1, 1))
        let model =
            float4x4.translation(SIMD3(position.x, position.y, position.z))
            * float4x4.rotationX(rotationAngle) * float4x4.rotationY(.pi / 6)
            * float4x4.rotationX(.pi / 6) * scale

        return CubeData(
            transform: projection * view * model,
            color: self.color
        )
    }
}

class MetalView: NSView {
    private var metalLayer: CAMetalLayer!
    private var device: MTLDevice!
    private var commandQueue: MTLCommandQueue!
    @available(macOS 15.0, *)
    private var displayLink: CADisplayLink?
    private var pipelineState: MTLRenderPipelineState!
    private var depthState: MTLDepthStencilState!
    private var cubes = [
        Cube(
            position: SIMD4<Float>(0.2, 0, 0, 0),
            color: SIMD4<Float>(1, 0, 0, 0)
        ),
        Cube(
            position: SIMD4<Float>(0, 0.2, 0, 0),
            color: SIMD4<Float>(0, 1, 0, 0)
        ),
        Cube(
            position: SIMD4<Float>(0, 0, -0.2, 0),
            color: SIMD4<Float>(0, 0, 1, 0)
        ),
        Cube(
            position: SIMD4<Float>(0, 0, 0, 0),
            color: SIMD4<Float>(1, 1, 0, 0)
        ),
    ]

    struct Vertex {
        var position: SIMD4<Float>
        var normal: SIMD3<Float>
    }

    private var transformBuffer: MTLBuffer!
    private var vertexBuffer: MTLBuffer!

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }

    required init?(coder decoder: NSCoder) {
        super.init(coder: decoder)
        commonInit()
    }

    private func commonInit() {
        wantsLayer = true
        device = MTLCreateSystemDefaultDevice()
        metalLayer = CAMetalLayer()
        metalLayer.device = device
        metalLayer.pixelFormat = .bgra8Unorm
        metalLayer.framebufferOnly = true
        metalLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2.0
        buildCubeVertices()
        layer = metalLayer
        commandQueue = device.makeCommandQueue()
        buildDepthState()
        buildPipeline()
        if #available(macOS 15.0, *) {
            setupDisplayLink()
        }
    }

    @available(macOS 15.0, *)
    private func setupDisplayLink() {
        displayLink = self.displayLink(
            target: self,
            selector: #selector(drawFrame)
        )
        displayLink?.preferredFrameRateRange = CAFrameRateRange(
            minimum: 30,
            maximum: 60,
            preferred: 60
        )
        displayLink?.isPaused = false
        displayLink?.add(to: .current, forMode: .common)
    }

    @objc private func drawFrame() {
        guard let drawable = metalLayer.nextDrawable() else { return }

        let depthDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .depth32Float,
            width: Int(drawable.texture.width),
            height: Int(drawable.texture.height),
            mipmapped: false
        )
        depthDesc.usage = [.renderTarget]
        depthDesc.storageMode = .private
        let depthTexture = device.makeTexture(descriptor: depthDesc)

        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = drawable.texture
        descriptor.colorAttachments[0].loadAction = .clear
        descriptor.colorAttachments[0].clearColor = MTLClearColor(
            red: 0.1,
            green: 0.1,
            blue: 0.25,
            alpha: 1
        )
        descriptor.colorAttachments[0].storeAction = .store

        descriptor.depthAttachment.texture = depthTexture
        descriptor.depthAttachment.loadAction = .clear
        descriptor.depthAttachment.clearDepth = 1.0
        descriptor.depthAttachment.storeAction = .dontCare

        guard let commandBuffer = commandQueue.makeCommandBuffer(),
            let encoder = commandBuffer.makeRenderCommandEncoder(
                descriptor: descriptor
            )
        else {
            return
        }

        updateTransform()

        encoder.setRenderPipelineState(pipelineState)
        encoder.setDepthStencilState(depthState)
        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        encoder.setVertexBuffer(transformBuffer, offset: 0, index: 1)
        encoder.drawPrimitives(
            type: .triangle,
            vertexStart: 0,
            vertexCount: vertexBuffer.length / MemoryLayout<Vertex>.stride,
            instanceCount: cubes.count
        )
        encoder.setCullMode(.back)
        encoder.setFrontFacing(.counterClockwise)
        encoder.endEncoding()

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        metalLayer.frame = CGRect(origin: .zero, size: newSize)
    }

    private func buildPipeline() {
        guard let library = device.makeDefaultLibrary() else {
            fatalError("Could not load Metal library")
        }

        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = library.makeFunction(
            name: "vertex_main"
        )
        pipelineDescriptor.fragmentFunction = library.makeFunction(
            name: "fragment_main"
        )
        pipelineDescriptor.colorAttachments[0].pixelFormat =
            metalLayer.pixelFormat
        pipelineDescriptor.depthAttachmentPixelFormat = .depth32Float

        do {
            pipelineState = try device.makeRenderPipelineState(
                descriptor: pipelineDescriptor
            )
        } catch {
            fatalError("Failed to create pipeline state: \(error)")
        }
    }

    private func buildCubeVertices() {
        var vertices: [Vertex] = []

        func addFace(
            _ a: SIMD4<Float>,
            _ b: SIMD4<Float>,
            _ c: SIMD4<Float>,
            _ d: SIMD4<Float>,
            normal: SIMD3<Float>
        ) {
            vertices.append(Vertex(position: a, normal: normal))
            vertices.append(Vertex(position: c, normal: normal))
            vertices.append(Vertex(position: b, normal: normal))

            vertices.append(Vertex(position: a, normal: normal))
            vertices.append(Vertex(position: d, normal: normal))
            vertices.append(Vertex(position: c, normal: normal))
        }

        let p000 = SIMD4<Float>(-0.5, -0.5, -0.5, 1)
        let p001 = SIMD4<Float>(-0.5, -0.5, 0.5, 1)
        let p010 = SIMD4<Float>(-0.5, 0.5, -0.5, 1)
        let p011 = SIMD4<Float>(-0.5, 0.5, 0.5, 1)
        let p100 = SIMD4<Float>(0.5, -0.5, -0.5, 1)
        let p101 = SIMD4<Float>(0.5, -0.5, 0.5, 1)
        let p110 = SIMD4<Float>(0.5, 0.5, -0.5, 1)
        let p111 = SIMD4<Float>(0.5, 0.5, 0.5, 1)

        // Front
        addFace(p011, p001, p101, p111, normal: SIMD3<Float>(0, 0, 1))
        // Back
        addFace(p110, p100, p000, p010, normal: SIMD3<Float>(0, 0, -1))
        // Left
        addFace(p010, p000, p001, p011, normal: SIMD3<Float>(0, 1, 0))
        // Right
        addFace(p111, p101, p100, p110, normal: SIMD3<Float>(1, 0, 0))
        // Top
        addFace(p010, p011, p111, p110, normal: SIMD3<Float>(0,  1, 0))
        // Bottom
        addFace(p001, p000, p100, p101, normal: SIMD3<Float>(1, 0, 0))

        vertexBuffer = device.makeBuffer(
            bytes: vertices,
            length: vertices.count * MemoryLayout<Vertex>.stride,
            options: []
        )
    }

    private func updateTransform() {
        let aspect = Float(self.bounds.width / self.bounds.height)
        var instanceDatas: [CubeData] = []
        for cube in cubes {
            instanceDatas.append(cube.updateTransform(aspect: aspect))
        }
        transformBuffer = device.makeBuffer(
            bytes: instanceDatas,
            length: instanceDatas.count * MemoryLayout<CubeData>.stride,
            options: []
        )
    }

    private func buildDepthState() {
        let depthDesc = MTLDepthStencilDescriptor()
        depthDesc.depthCompareFunction = .less
        depthDesc.isDepthWriteEnabled = true
        depthState = device.makeDepthStencilState(descriptor: depthDesc)
    }

}
