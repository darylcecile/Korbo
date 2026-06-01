import SwiftUI
import PencilKit

/// UIViewRepresentable wrapping PKCanvasView for Apple Pencil / finger sketching.
struct ScribbleCanvas: UIViewRepresentable {
    @Binding var drawing: PKDrawing
    let backgroundColor: UIColor

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.drawing = drawing
        canvas.drawingPolicy = .anyInput  // finger works in simulator
        canvas.backgroundColor = backgroundColor
        canvas.delegate = context.coordinator
        canvas.tool = PKInkingTool(.pen, color: .black, width: 4)
        canvas.isOpaque = false
        return canvas
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {
        // Sync external drawing changes if needed (one-way binding for now)
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, PKCanvasViewDelegate {
        var parent: ScribbleCanvas
        init(_ parent: ScribbleCanvas) { self.parent = parent }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            parent.drawing = canvasView.drawing
        }
    }
}

/// Sheet presenting a sketch canvas with minimal controls and attach/cancel actions.
struct ScribbleSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var drawing = PKDrawing()
    @State private var selectedTool: SketchTool = .pen

    let onAttach: (UIImage) -> Void

    enum SketchTool: String, CaseIterable, Identifiable {
        case pen, eraser
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                toolbar
                Divider()
                ScribbleCanvas(drawing: $drawing, backgroundColor: .white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(Color.white)
            .navigationTitle("Sketch")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Attach") { attach() }
                        .disabled(drawing.bounds.isEmpty)
                }
            }
        }
        .presentationDetents([.large])
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
        guard !drawing.bounds.isEmpty else { return }
        let bounds = drawing.bounds.insetBy(dx: -20, dy: -20)  // small padding
        let image = drawing.image(from: bounds, scale: UIScreen.main.scale)

        // Composite onto white background
        let format = UIGraphicsImageRendererFormat()
        format.scale = UIScreen.main.scale
        let renderer = UIGraphicsImageRenderer(size: bounds.size, format: format)
        let finalImage = renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: bounds.size))
            image.draw(at: .zero)
        }

        onAttach(finalImage)
        dismiss()
    }
}
