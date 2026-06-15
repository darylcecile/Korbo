import SwiftUI
import PencilKit
import AVFoundation

/// The drawing tools available in the sketch canvas.
enum SketchTool: String, CaseIterable, Identifiable {
    case pen, eraser
    var id: String { rawValue }
}

/// UIViewRepresentable wrapping PKCanvasView for Apple Pencil / finger sketching.
struct ScribbleCanvas: UIViewRepresentable {
    @Binding var drawing: PKDrawing
    var tool: SketchTool
    let backgroundColor: UIColor

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.drawing = drawing
        canvas.drawingPolicy = .anyInput
        canvas.backgroundColor = backgroundColor
        canvas.isOpaque = false
        canvas.delegate = context.coordinator
        canvas.tool = Self.pkTool(for: tool)
        // PencilKit adapts ink colours to the active interface style so they stay
        // visible on a dark background. This canvas draws on a light "paper", so
        // force light mode — otherwise black ink is inverted to white and renders
        // invisibly on the white background. (Verified on-device: the drawing data
        // is present with valid bounds, but nothing shows because it's white-on-white.)
        canvas.overrideUserInterfaceStyle = .light
        context.coordinator.appliedTool = tool
        return canvas
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {
        context.coordinator.parent = self
        // Keep the live tool in step with the toolbar selection.
        if context.coordinator.appliedTool != tool {
            uiView.tool = Self.pkTool(for: tool)
            context.coordinator.appliedTool = tool
        }
        // Reflect programmatic drawing changes (e.g. the Clear button) back into the
        // canvas. The delegate keeps `drawing` in step with user input, so a
        // differing stroke count signals an external mutation we must apply.
        if uiView.drawing.strokes.count != drawing.strokes.count {
            uiView.drawing = drawing
        }
    }

    private static func pkTool(for tool: SketchTool) -> PKTool {
        switch tool {
        case .pen: return PKInkingTool(.pen, color: .black, width: 4)
        case .eraser: return PKEraserTool(.bitmap)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, PKCanvasViewDelegate {
        var parent: ScribbleCanvas
        var appliedTool: SketchTool = .pen
        init(_ parent: ScribbleCanvas) { self.parent = parent }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            parent.drawing = canvasView.drawing
        }
    }
}

/// Sheet presenting a sketch canvas with minimal controls and attach/cancel actions.
/// When `backgroundImage` is set, the canvas annotates that image instead of a
/// blank page — useful for marking up a screenshot to point out changes.
struct ScribbleSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var drawing = PKDrawing()
    @State private var selectedTool: SketchTool = .pen
    @State private var canvasSize: CGSize = .zero

    var backgroundImage: UIImage?
    let onAttach: (UIImage) -> Void

    private var isAnnotating: Bool { backgroundImage != nil }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                toolbar
                Divider()
                canvasArea
            }
            .background(isAnnotating ? Color(.systemGray5) : Color.white)
            .navigationTitle(isAnnotating ? "Markup" : "Sketch")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Attach") { attach() }
                        .disabled(!isAnnotating && drawing.bounds.isEmpty)
                }
            }
        }
        .presentationDetents([.large])
    }

    @ViewBuilder
    private var canvasArea: some View {
        if let backgroundImage {
            GeometryReader { geo in
                ZStack {
                    Image(uiImage: backgroundImage)
                        .resizable()
                        .scaledToFit()
                    ScribbleCanvas(drawing: $drawing, tool: selectedTool, backgroundColor: .clear)
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .onAppear { canvasSize = geo.size }
                .onChange(of: geo.size) { _, newValue in canvasSize = newValue }
            }
        } else {
            ScribbleCanvas(drawing: $drawing, tool: selectedTool, backgroundColor: .white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var toolbar: some View {
        HStack(spacing: 20) {
            ForEach(SketchTool.allCases) { tool in
                Button {
                    selectedTool = tool
                } label: {
                    Image(systemName: tool == .pen ? "pencil.tip" : "eraser")
                        .font(.system(size: 18))
                        .foregroundStyle(selectedTool == tool ? Theme.accent : Theme.textSecondary)
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(selectedTool == tool ? Theme.accent.opacity(0.15) : Color.clear)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tool == .pen ? "Pen tool" : "Eraser tool")
                .accessibilityAddTraits(selectedTool == tool ? [.isSelected] : [])
            }
            Spacer()
            Button {
                drawing = PKDrawing()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.textSecondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Clear canvas")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Theme.panelRaised)
    }

    private func attach() {
        let result: UIImage
        if let backgroundImage {
            result = annotatedImage(over: backgroundImage)
        } else {
            guard !drawing.bounds.isEmpty else { return }
            result = blankSketchImage()
        }
        onAttach(result)
        dismiss()
    }

    /// Flatten the ink onto a white page (blank-sketch mode).
    private func blankSketchImage() -> UIImage {
        let bounds = drawing.bounds.insetBy(dx: -20, dy: -20)  // small padding
        let scale = UIScreen.main.scale
        let ink = lightModeInk(from: bounds, scale: scale)

        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        let renderer = UIGraphicsImageRenderer(size: bounds.size, format: format)
        return renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: bounds.size))
            ink.draw(at: .zero)
        }
    }

    /// Composite the ink onto the source image (annotate mode).
    ///
    /// The ink is captured in the canvas's point space, so we render only the region
    /// the image actually occupies on screen (`fitted`) and stretch it to the image's
    /// own size — keeping annotations aligned with the underlying picture.
    private func annotatedImage(over image: UIImage) -> UIImage {
        guard canvasSize.width > 0, canvasSize.height > 0 else { return image }
        let canvasRect = CGRect(origin: .zero, size: canvasSize)
        let fitted = AVMakeRect(aspectRatio: image.size, insideRect: canvasRect)
        let ink = lightModeInk(from: fitted, scale: image.scale)

        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        let renderer = UIGraphicsImageRenderer(size: image.size, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
            ink.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }

    /// Render the drawing forcing light mode so PencilKit doesn't invert black ink
    /// to white (mirrors `ScribbleCanvas`'s `overrideUserInterfaceStyle`).
    private func lightModeInk(from rect: CGRect, scale: CGFloat) -> UIImage {
        var ink = UIImage()
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
            ink = drawing.image(from: rect, scale: scale)
        }
        return ink
    }
}
