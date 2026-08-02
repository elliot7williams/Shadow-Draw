import SwiftUI
import Combine

struct ContentView: View {
    var body: some View {
        ShadowArtDrawingView()
    }
}

struct ShadowArtDrawingView: View {
    @StateObject private var drawingManager = DrawingManager()
    @State private var currentPath = Path()
    @State private var isDrawing = false
    @State private var lastDrawPoint: CGPoint?
    
    // Advanced UI State
    @State private var showControls = true
    @State private var selectedPanel: ControlPanel = .tools
    @State private var showLayerPanel = false
    @State private var showAnimationPanel = false
    @State private var showExportPanel = false
    @State private var showHistoryPanel = false
    
    // Canvas state
    @State private var canvasScale: CGFloat = 1.0
    @State private var canvasOffset = CGSize.zero
    @State private var showGrid = true
    @State private var gridSize: CGFloat = 20
    @State private var canvasSize = CGSize(width: 800, height: 600)
    
    // Animation
    @State private var animationTimer: Timer?
    @State private var isAnimating = false
    @State private var animationFrame = 0
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Dynamic background
                RadialGradient(
                    colors: [drawingManager.backgroundColor, drawingManager.backgroundColor.opacity(0.3)],
                    center: .center,
                    startRadius: 0,
                    endRadius: 400
                )
                .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Top toolbar
                    topToolbar
                    
                    // Main canvas area
                    HStack(spacing: 0) {
                        // Left sidebar
                        if showLayerPanel {
                            layerPanel
                                .frame(width: 250)
                                .transition(.move(edge: .leading))
                        }
                        
                        // Canvas
                        canvasView(geometry: geometry)
                        
                        // Right sidebar
                        if showHistoryPanel {
                            historyPanel
                                .frame(width: 200)
                                .transition(.move(edge: .trailing))
                        }
                    }
                    
                    // Bottom controls
                    if showControls {
                        controlsPanel
                            .transition(.move(edge: .bottom))
                    }
                    
                    // Animation panel
                    if showAnimationPanel {
                        animationPanel
                            .transition(.move(edge: .bottom))
                    }
                    
                    // Export panel
                    if showExportPanel {
                        exportPanel
                            .transition(.move(edge: .bottom))
                    }
                }
                
                // Floating action buttons
                floatingActionButtons
            }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: showControls)
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: showLayerPanel)
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: showAnimationPanel)
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: showExportPanel)
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: showHistoryPanel)
    }
    
    // MARK: - Top Toolbar
    private var topToolbar: some View {
        HStack {
            // App title with glow effect
            Text("Shadow Art Studio")
                .font(.title2.bold())
                .foregroundColor(.white)
                .shadow(color: .cyan, radius: 5)
            
            Spacer()
            
            // Canvas controls
            HStack(spacing: 15) {
                Button(action: { showGrid.toggle() }) {
                    Image(systemName: showGrid ? "grid" : "grid.slash")
                        .foregroundColor(showGrid ? .cyan : .gray)
                }
                
                Button(action: resetCanvas) {
                    Image(systemName: "arrow.clockwise")
                        .foregroundColor(.yellow)
                }
                
                Button(action: { drawingManager.clearAll() }) {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                }
            }
            .font(.title3)
        }
        .padding()
        .background(Color.black.opacity(0.8))
    }
    
    // MARK: - Canvas View
    private func canvasView(geometry: GeometryProxy) -> some View {
        ZStack {
            // Canvas background with texture
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [Color.black.opacity(0.9), Color.gray.opacity(0.1)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    // Advanced grid
                    Canvas { context, size in
                        if showGrid {
                            let spacing = gridSize * canvasScale
                            context.stroke(
                                Path { path in
                                    for x in stride(from: 0, through: size.width, by: spacing) {
                                        path.move(to: CGPoint(x: x, y: 0))
                                        path.addLine(to: CGPoint(x: x, y: size.height))
                                    }
                                    for y in stride(from: 0, through: size.height, by: spacing) {
                                        path.move(to: CGPoint(x: 0, y: y))
                                        path.addLine(to: CGPoint(x: size.width, y: y))
                                    }
                                },
                                with: .color(.white.opacity(0.1)),
                                lineWidth: 0.5
                            )
                        }
                    }
                )
            
            // Layers rendering
            ForEach(drawingManager.layers.indices, id: \.self) { layerIndex in
                if drawingManager.layers[layerIndex].isVisible {
                    layerView(layer: drawingManager.layers[layerIndex])
                        .opacity(drawingManager.layers[layerIndex].opacity)
                        .blendMode(drawingManager.layers[layerIndex].blendMode.swiftUIBlendMode)
                }
            }
            
            // Current drawing path
            currentPath
                .stroke(
                    drawingManager.currentTool.strokeColor,
                    style: StrokeStyle(
                        lineWidth: drawingManager.currentTool.strokeWidth,
                        lineCap: drawingManager.currentTool.lineCap.cgLineCap,
                        lineJoin: drawingManager.currentTool.lineJoin.cgLineJoin
                    )
                )
                .applyShadowEffect(drawingManager.currentTool.shadowSettings)
                .applyTextureEffect(drawingManager.currentTool.textureSettings)
            
            // Particle effects overlay
            ForEach(drawingManager.particleEffects.indices, id: \.self) { index in
                particleEffectView(effect: drawingManager.particleEffects[index])
            }
        }
        .scaleEffect(canvasScale)
        .offset(canvasOffset)
        .clipped()
        .gesture(
            SimultaneousGesture(
                // Drawing gesture
                DragGesture(minimumDistance: 0)
                    .onChanged(handleDrawing)
                    .onEnded(finishDrawing),
                
                // Pan and zoom gestures
                MagnificationGesture()
                    .onChanged { value in
                        canvasScale = max(0.5, min(3.0, value))
                    }
            )
        )
        .gesture(
            DragGesture()
                .onChanged { value in
                    if drawingManager.currentTool.type == .pan {
                        canvasOffset = value.translation
                    }
                }
        )
    }
    
    // MARK: - Layer View
    private func layerView(layer: DrawingLayer) -> some View {
        ForEach(layer.paths.indices, id: \.self) { pathIndex in
            let shadowPath = layer.paths[pathIndex]
            shadowPath.path
                .stroke(
                    shadowPath.strokeColor,
                    style: StrokeStyle(
                        lineWidth: shadowPath.strokeWidth,
                        lineCap: shadowPath.lineCap.cgLineCap,
                        lineJoin: shadowPath.lineJoin.cgLineJoin
                    )
                )
                .applyShadowEffect(shadowPath.shadowSettings)
                .applyTextureEffect(shadowPath.textureSettings)
                .applyAnimationEffect(shadowPath.animationSettings, frame: animationFrame)
        }
    }
    
    // MARK: - Particle Effect View
    private func particleEffectView(effect: ParticleEffect) -> some View {
        Canvas { context, size in
            for particle in effect.particles {
                let center = CGPoint(x: particle.x, y: particle.y)
                let rect = CGRect(
                    origin: CGPoint(x: center.x - particle.size/2, y: center.y - particle.size/2),
                    size: CGSize(width: particle.size, height: particle.size)
                )
                
                context.fill(
                    Path(ellipseIn: rect),
                    with: .color(particle.color.opacity(particle.alpha))
                )
            }
        }
    }
    
    // MARK: - Controls Panel
    private var controlsPanel: some View {
        VStack(spacing: 0) {
            // Panel selector
            HStack {
                ForEach(ControlPanel.allCases, id: \.self) { panel in
                    Button(action: { selectedPanel = panel }) {
                        VStack {
                            Image(systemName: panel.icon)
                            Text(panel.title)
                                .font(.caption)
                        }
                        .foregroundColor(selectedPanel == panel ? .cyan : .gray)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(selectedPanel == panel ? Color.cyan.opacity(0.2) : Color.clear)
                        )
                    }
                }
                Spacer()
            }
            .padding(.horizontal)
            .padding(.top, 10)
            
            Divider().background(Color.gray)
            
            // Panel content
            ScrollView {
                switch selectedPanel {
                case .tools:
                    toolsPanel
                case .shadows:
                    shadowsPanel
                case .effects:
                    effectsPanel
                case .colors:
                    colorsPanel
                case .brushes:
                    brushesPanel
                }
            }
            .frame(maxHeight: 300)
        }
        .background(Color.black.opacity(0.9))
    }
    
    // MARK: - Tools Panel
    private var toolsPanel: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 15) {
            ForEach(ToolType.allCases, id: \.self) { tool in
                Button(action: { drawingManager.selectTool(tool) }) {
                    VStack {
                        Image(systemName: tool.icon)
                            .font(.title2)
                        Text(tool.name)
                            .font(.caption)
                    }
                    .foregroundColor(drawingManager.currentTool.type == tool ? .cyan : .white)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(drawingManager.currentTool.type == tool ? Color.cyan.opacity(0.3) : Color.gray.opacity(0.2))
                    )
                }
            }
        }
        .padding()
    }
    
    // MARK: - Shadows Panel
    private var shadowsPanel: some View {
        VStack(alignment: .leading, spacing: 15) {
            // Multiple shadow layers
            ForEach(drawingManager.currentTool.shadowSettings.layers.indices, id: \.self) { index in
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Shadow Layer \(index + 1)")
                            .foregroundColor(.white)
                            .font(.headline)
                        Spacer()
                        Button(action: { drawingManager.removeShadowLayer(index) }) {
                            Image(systemName: "minus.circle")
                                .foregroundColor(.red)
                        }
                    }
                    
                    shadowLayerControls(for: index)
                }
                .padding()
                .background(Color.gray.opacity(0.2))
                .cornerRadius(10)
            }
            
            Button(action: { drawingManager.addShadowLayer() }) {
                HStack {
                    Image(systemName: "plus.circle")
                    Text("Add Shadow Layer")
                }
                .foregroundColor(.cyan)
                .padding()
                .background(Color.cyan.opacity(0.2))
                .cornerRadius(8)
            }
            
            // Shadow presets
            shadowPresetsGrid
        }
        .padding()
    }
    
    private func shadowLayerControls(for index: Int) -> some View {
        VStack(spacing: 10) {
            ColorPicker("Color", selection: Binding(
                get: { drawingManager.currentTool.shadowSettings.layers[index].color },
                set: { drawingManager.updateShadowLayer(index, color: $0) }
            ))
            
            HStack {
                Text("Blur: \(Int(drawingManager.currentTool.shadowSettings.layers[index].radius))")
                    .foregroundColor(.white)
                Spacer()
                Slider(
                    value: Binding(
                        get: { drawingManager.currentTool.shadowSettings.layers[index].radius },
                        set: { drawingManager.updateShadowLayer(index, radius: $0) }
                    ),
                    in: 0...100
                )
                .accentColor(.cyan)
            }
            
            HStack {
                Text("X: \(Int(drawingManager.currentTool.shadowSettings.layers[index].offsetX))")
                    .foregroundColor(.white)
                Spacer()
                Slider(
                    value: Binding(
                        get: { drawingManager.currentTool.shadowSettings.layers[index].offsetX },
                        set: { drawingManager.updateShadowLayer(index, offsetX: $0) }
                    ),
                    in: -100...100
                )
                .accentColor(.cyan)
            }
            
            HStack {
                Text("Y: \(Int(drawingManager.currentTool.shadowSettings.layers[index].offsetY))")
                    .foregroundColor(.white)
                Spacer()
                Slider(
                    value: Binding(
                        get: { drawingManager.currentTool.shadowSettings.layers[index].offsetY },
                        set: { drawingManager.updateShadowLayer(index, offsetY: $0) }
                    ),
                    in: -100...100
                )
                .accentColor(.cyan)
            }
            
            HStack {
                Text("Opacity: \(Int(drawingManager.currentTool.shadowSettings.layers[index].opacity * 100))%")
                    .foregroundColor(.white)
                Spacer()
                Slider(
                    value: Binding(
                        get: { drawingManager.currentTool.shadowSettings.layers[index].opacity },
                        set: { drawingManager.updateShadowLayer(index, opacity: $0) }
                    ),
                    in: 0...1
                )
                .accentColor(.cyan)
            }
        }
    }
    
    // MARK: - Shadow Presets Grid
    private var shadowPresetsGrid: some View {
        VStack(alignment: .leading) {
            Text("Shadow Presets")
                .foregroundColor(.white)
                .font(.headline)
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 10) {
                ForEach(ShadowPreset.allCases, id: \.self) { preset in
                    Button(action: { drawingManager.applyShadowPreset(preset) }) {
                        VStack {
                            Text(preset.name)
                                .font(.caption)
                                .foregroundColor(.white)
                            Rectangle()
                                .fill(Color.white)
                                .frame(height: 30)
                                .applyShadowPreset(preset)
                        }
                        .padding(8)
                        .background(Color.gray.opacity(0.3))
                        .cornerRadius(8)
                    }
                }
            }
        }
    }
    
    // MARK: - Effects Panel
    private var effectsPanel: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Texture effects
            VStack(alignment: .leading) {
                Text("Texture Effects")
                    .foregroundColor(.white)
                    .font(.headline)
                
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 10) {
                    ForEach(TextureType.allCases, id: \.self) { texture in
                        Button(action: { drawingManager.setTexture(texture) }) {
                            VStack {
                                Image(systemName: texture.icon)
                                    .font(.title2)
                                Text(texture.name)
                                    .font(.caption)
                            }
                            .foregroundColor(drawingManager.currentTool.textureSettings.type == texture ? .cyan : .white)
                            .padding(10)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(drawingManager.currentTool.textureSettings.type == texture ? Color.cyan.opacity(0.3) : Color.gray.opacity(0.2))
                            )
                        }
                    }
                }
            }
            
            // Particle effects
            VStack(alignment: .leading) {
                Text("Particle Effects")
                    .foregroundColor(.white)
                    .font(.headline)
                
                HStack {
                    Button("Sparkles") { drawingManager.addParticleEffect(.sparkles) }
                    Button("Fire") { drawingManager.addParticleEffect(.fire) }
                    Button("Snow") { drawingManager.addParticleEffect(.snow) }
                    Button("Magic") { drawingManager.addParticleEffect(.magic) }
                }
                .buttonStyle(EffectButtonStyle())
            }
            
            // Animation effects
            VStack(alignment: .leading) {
                Text("Animation Effects")
                    .foregroundColor(.white)
                    .font(.headline)
                
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 10) {
                    ForEach(AnimationType.allCases, id: \.self) { animation in
                        Button(action: { drawingManager.setAnimation(animation) }) {
                            VStack {
                                Image(systemName: animation.icon)
                                Text(animation.name)
                                    .font(.caption)
                            }
                            .foregroundColor(.white)
                            .padding(8)
                            .background(Color.gray.opacity(0.3))
                            .cornerRadius(8)
                        }
                    }
                }
            }
        }
        .padding()
    }
    
    // MARK: - Colors Panel
    private var colorsPanel: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Color picker
            VStack(alignment: .leading) {
                Text("Stroke Color")
                    .foregroundColor(.white)
                    .font(.headline)
                ColorPicker("", selection: $drawingManager.currentTool.strokeColor)
                    .frame(height: 50)
            }
            
            // Color palette
            VStack(alignment: .leading) {
                Text("Quick Colors")
                    .foregroundColor(.white)
                    .font(.headline)
                
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 8), spacing: 8) {
                    ForEach(ColorPalette.defaultColors, id: \.self) { color in
                        Button(action: { drawingManager.currentTool.strokeColor = color }) {
                            Circle()
                                .fill(color)
                                .frame(width: 30, height: 30)
                                .overlay(
                                    Circle()
                                        .stroke(Color.white, lineWidth: drawingManager.currentTool.strokeColor == color ? 2 : 0)
                                )
                        }
                    }
                }
            }
            
            // Gradient options
            VStack(alignment: .leading) {
                Text("Gradients")
                    .foregroundColor(.white)
                    .font(.headline)
                
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 10) {
                    ForEach(GradientType.allCases, id: \.self) { gradient in
                        Button(action: { drawingManager.setGradient(gradient) }) {
                            Rectangle()
                                .fill(gradient.gradient)
                                .frame(height: 40)
                                .cornerRadius(8)
                                .overlay(
                                    Text(gradient.name)
                                        .font(.caption)
                                        .foregroundColor(.white)
                                        .shadow(radius: 2)
                                )
                        }
                    }
                }
            }
        }
        .padding()
    }
    
    // MARK: - Brushes Panel
    private var brushesPanel: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Brush size
            VStack(alignment: .leading) {
                HStack {
                    Text("Size: \(Int(drawingManager.currentTool.strokeWidth))")
                        .foregroundColor(.white)
                    Spacer()
                    Slider(value: $drawingManager.currentTool.strokeWidth, in: 1...100)
                        .accentColor(.cyan)
                }
            }
            
            // Brush opacity
            VStack(alignment: .leading) {
                HStack {
                    Text("Opacity: \(Int(drawingManager.currentTool.opacity * 100))%")
                        .foregroundColor(.white)
                    Spacer()
                    Slider(value: $drawingManager.currentTool.opacity, in: 0...1)
                        .accentColor(.cyan)
                }
            }
            
            // Line caps and joins
            VStack(alignment: .leading) {
                Text("Line Style")
                    .foregroundColor(.white)
                    .font(.headline)
                
                HStack {
                    Text("Cap:")
                        .foregroundColor(.white)
                    Picker("", selection: $drawingManager.currentTool.lineCap) {
                        ForEach(LineCap.allCases, id: \.self) { cap in
                            Text(cap.name).tag(cap)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                }
                
                HStack {
                    Text("Join:")
                        .foregroundColor(.white)
                    Picker("", selection: $drawingManager.currentTool.lineJoin) {
                        ForEach(LineJoin.allCases, id: \.self) { join in
                            Text(join.name).tag(join)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                }
            }
            
            // Brush presets
            VStack(alignment: .leading) {
                Text("Brush Presets")
                    .foregroundColor(.white)
                    .font(.headline)
                
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 10) {
                    ForEach(BrushPreset.allCases, id: \.self) { preset in
                        Button(action: { drawingManager.applyBrushPreset(preset) }) {
                            VStack {
                                Image(systemName: preset.icon)
                                    .font(.title2)
                                Text(preset.name)
                                    .font(.caption)
                            }
                            .foregroundColor(.white)
                            .padding(10)
                            .background(Color.gray.opacity(0.3))
                            .cornerRadius(8)
                        }
                    }
                }
            }
        }
        .padding()
    }
    
    // MARK: - Layer Panel
    private var layerPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Layers")
                    .foregroundColor(.white)
                    .font(.headline)
                Spacer()
                Button(action: { drawingManager.addLayer() }) {
                    Image(systemName: "plus.circle")
                        .foregroundColor(.cyan)
                }
            }
            .padding()
            
            ScrollView {
                LazyVStack(spacing: 5) {
                    ForEach(drawingManager.layers.indices.reversed(), id: \.self) { index in
                        layerRowView(layer: drawingManager.layers[index], index: index)
                    }
                }
            }
            
            Spacer()
        }
        .background(Color.black.opacity(0.9))
    }
    
    private func layerRowView(layer: DrawingLayer, index: Int) -> some View {
        HStack {
            Button(action: { drawingManager.toggleLayerVisibility(index) }) {
                Image(systemName: layer.isVisible ? "eye" : "eye.slash")
                    .foregroundColor(layer.isVisible ? .cyan : .gray)
            }
            
            VStack(alignment: .leading) {
                Text(layer.name)
                    .foregroundColor(.white)
                    .font(.caption)
                Text("\(layer.paths.count) paths")
                    .foregroundColor(.gray)
                    .font(.caption2)
            }
            
            Spacer()
            
            Text("\(Int(layer.opacity * 100))%")
                .foregroundColor(.gray)
                .font(.caption2)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(drawingManager.currentLayerIndex == index ? Color.cyan.opacity(0.3) : Color.gray.opacity(0.2))
        )
        .onTapGesture {
            drawingManager.selectLayer(index)
        }
    }
    
    // MARK: - Animation Panel
    private var animationPanel: some View {
        VStack(spacing: 15) {
            HStack {
                Text("Animation Studio")
                    .foregroundColor(.white)
                    .font(.headline)
                Spacer()
                Button(isAnimating ? "Stop" : "Play") {
                    toggleAnimation()
                }
                .foregroundColor(isAnimating ? .red : .green)
            }
            
            HStack {
                Text("Frame: \(animationFrame)")
                    .foregroundColor(.white)
                Spacer()
                Button("Previous") { previousFrame() }
                Button("Next") { nextFrame() }
            }
            .buttonStyle(AnimationButtonStyle())
        }
        .padding()
        .background(Color.black.opacity(0.9))
    }
    
    // MARK: - History Panel
    private var historyPanel: some View {
        VStack(alignment: .leading) {
            Text("History")
                .foregroundColor(.white)
                .font(.headline)
                .padding()
            
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 5) {
                    ForEach(drawingManager.history.indices.reversed(), id: \.self) { index in
                        Button(action: { drawingManager.restoreFromHistory(index) }) {
                            Text(drawingManager.history[index].description)
                                .foregroundColor(.white)
                                .font(.caption)
                                .padding(8)
                                .background(Color.gray.opacity(0.3))
                                .cornerRadius(6)
                        }
                    }
                }
            }
        }
        .background(Color.black.opacity(0.9))
    }
    
    // MARK: - Export Panel
    private var exportPanel: some View {
        VStack(spacing: 15) {
            Text("Export Options")
                .foregroundColor(.white)
                .font(.headline)
            
            HStack(spacing: 20) {
                Button("PNG") { exportImage(format: .png) }
                Button("SVG") { exportImage(format: .svg) }
                Button("GIF") { exportAnimation() }
                Button("Video") { exportVideo() }
            }
            .buttonStyle(ExportButtonStyle())
        }
        .padding()
        .background(Color.black.opacity(0.9))
    }
    
    // MARK: - Floating Action Buttons
    private var floatingActionButtons: some View {
        VStack {
            Spacer()
            HStack {
                VStack(spacing: 10) {
                    Button(action: { showLayerPanel.toggle() }) {
                        Image(systemName: "square.stack.3d.up")
                            .font(.title2)
                            .foregroundColor(.white)
                            .padding(12)
                            .background(Circle().fill(Color.cyan.opacity(0.8)))
                    }
                    
                    Button(action: { showHistoryPanel.toggle() }) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.title2)
                            .foregroundColor(.white)
                            .padding(12)
                            .background(Circle().fill(Color.orange.opacity(0.8)))
                    }
                    
                    Button(action: { showAnimationPanel.toggle() }) {
                        Image(systemName: "play.circle")
                            .font(.title2)
                            .foregroundColor(.white)
                            .padding(12)
                            .background(Circle().fill(Color.green.opacity(0.8)))
                    }
                    
                    Button(action: { showExportPanel.toggle() }) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.title2)
                            .foregroundColor(.white)
                            .padding(12)
                            .background(Circle().fill(Color.purple.opacity(0.8)))
                    }
                }
                
                Spacer()
                
                VStack(spacing: 10) {
                    Button(action: { drawingManager.undo() }) {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.title2)
                            .foregroundColor(.white)
                            .padding(12)
                            .background(Circle().fill(Color.yellow.opacity(0.8)))
                    }
                    
                    Button(action: { drawingManager.redo() }) {
                        Image(systemName: "arrow.uturn.forward")
                            .font(.title2)
                            .foregroundColor(.white)
                            .padding(12)
                            .background(Circle().fill(Color.blue.opacity(0.8)))
                    }
                }
            }
            .padding()
            
            // Main control toggle
            Button(action: { showControls.toggle() }) {
                Image(systemName: showControls ? "chevron.down" : "chevron.up")
                    .font(.title2)
                    .foregroundColor(.white)
                    .padding(15)
                    .background(Circle().fill(Color.black.opacity(0.8)))
            }
        }
    }
    
    // MARK: - Drawing Functions
    private func handleDrawing(_ value: DragGesture.Value) {
        let location = value.location
        
        if !isDrawing {
            currentPath = Path()
            currentPath.move(to: location)
            isDrawing = true
            lastDrawPoint = location
        } else {
            switch drawingManager.currentTool.type {
            case .brush, .pen:
                currentPath.addLine(to: location)
                
            case .spray:
                addSprayPoints(around: location)
                
            case .glow:
                addGlowPoints(from: lastDrawPoint ?? location, to: location)
                
            case .neon:
                addNeonEffect(from: lastDrawPoint ?? location, to: location)
                
            case .lightning:
                addLightningPath(from: lastDrawPoint ?? location, to: location)
                
            case .calligraphy:
                addCalligraphyStroke(from: lastDrawPoint ?? location, to: location)
                
            case .texture:
                addTexturedStroke(from: lastDrawPoint ?? location, to: location)
                
            case .eraser:
                eraseAtPoint(location)
                
            case .smudge:
                smudgeAtPoint(location)
                
            case .pan:
                // Handled in separate gesture
                break
            }
            
            lastDrawPoint = location
        }
        
        // Add particle effects based on tool
        if drawingManager.currentTool.hasParticleEffect {
            drawingManager.addParticleAt(location, type: drawingManager.currentTool.particleType)
        }
    }
    
    private func finishDrawing(_ value: DragGesture.Value) {
        if isDrawing {
            let shadowPath = ShadowPath(
                path: currentPath,
                strokeColor: drawingManager.currentTool.strokeColor,
                strokeWidth: drawingManager.currentTool.strokeWidth,
                shadowSettings: drawingManager.currentTool.shadowSettings,
                textureSettings: drawingManager.currentTool.textureSettings,
                animationSettings: drawingManager.currentTool.animationSettings,
                lineCap: drawingManager.currentTool.lineCap,
                lineJoin: drawingManager.currentTool.lineJoin,
                opacity: drawingManager.currentTool.opacity
            )
            
            drawingManager.addPath(shadowPath)
            drawingManager.saveToHistory("Draw with \(drawingManager.currentTool.type.name)")
            
            currentPath = Path()
            isDrawing = false
            lastDrawPoint = nil
        }
    }
    
    private func addSprayPoints(around location: CGPoint) {
        let sprayRadius = drawingManager.currentTool.sprayRadius
        let numberOfPoints = drawingManager.currentTool.sprayDensity
        
        for _ in 0..<numberOfPoints {
            let angle = Double.random(in: 0...(2 * Double.pi))
            let distance = CGFloat.random(in: 0...sprayRadius)
            let x = location.x + cos(angle) * distance
            let y = location.y + sin(angle) * distance
            let point = CGPoint(x: x, y: y)
            
            currentPath.addEllipse(in: CGRect(
                origin: CGPoint(x: point.x - 1, y: point.y - 1),
                size: CGSize(width: 2, height: 2)
            ))
        }
    }
    
    private func addGlowPoints(from startPoint: CGPoint, to endPoint: CGPoint) {
        let steps = 10
        for i in 0...steps {
            let t = CGFloat(i) / CGFloat(steps)
            let x = startPoint.x + (endPoint.x - startPoint.x) * t
            let y = startPoint.y + (endPoint.y - startPoint.y) * t
            let point = CGPoint(x: x, y: y)
            
            currentPath.addEllipse(in: CGRect(
                origin: CGPoint(x: point.x - 2, y: point.y - 2),
                size: CGSize(width: 4, height: 4)
            ))
        }
    }
    
    private func addNeonEffect(from startPoint: CGPoint, to endPoint: CGPoint) {
        currentPath.addLine(to: endPoint)
        // Add additional glow layers by drawing multiple paths
        for _ in 1...3 {
            var glowPath = Path()
            glowPath.move(to: startPoint)
            glowPath.addLine(to: endPoint)
        }
    }
    
    private func addLightningPath(from startPoint: CGPoint, to endPoint: CGPoint) {
        let segments = 8
        var currentPoint = startPoint
        
        for i in 1...segments {
            let t = CGFloat(i) / CGFloat(segments)
            let baseX = startPoint.x + (endPoint.x - startPoint.x) * t
            let baseY = startPoint.y + (endPoint.y - startPoint.y) * t
            
            let randomOffsetX = CGFloat.random(in: -10...10)
            let randomOffsetY = CGFloat.random(in: -10...10)
            
            let nextPoint = CGPoint(x: baseX + randomOffsetX, y: baseY + randomOffsetY)
            currentPath.addLine(to: nextPoint)
            currentPoint = nextPoint
        }
        currentPath.addLine(to: endPoint)
    }
    
    private func addCalligraphyStroke(from startPoint: CGPoint, to endPoint: CGPoint) {
        let dx = endPoint.x - startPoint.x
        let dy = endPoint.y - startPoint.y
        let angle = atan2(dy, dx)
        let width = drawingManager.currentTool.strokeWidth
        
        // Create variable width stroke
        let perpAngle = angle + .pi / 2
        let offset = width / 4
        
        // Use CGFloat versions of trig functions
        let p1 = CGPoint(
            x: startPoint.x + CGFloat(cos(perpAngle)) * offset,
            y: startPoint.y + CGFloat(sin(perpAngle)) * offset
        )
        let p2 = CGPoint(
                x: startPoint.x - CGFloat(cos(perpAngle)) * offset,
                y: startPoint.y - CGFloat(sin(perpAngle)) * offset
        )
        let p3 = CGPoint(
            x: endPoint.x - CGFloat(cos(perpAngle)) * offset,
            y: endPoint.y - CGFloat(sin(perpAngle)) * offset
        )
        let p4 = CGPoint(
            x: endPoint.x + CGFloat(cos(perpAngle)) * offset,
            y: endPoint.y + CGFloat(sin(perpAngle)) * offset
        )
        
        currentPath.move(to: p1)
        currentPath.addLine(to: p2)
        currentPath.addLine(to: p3)
        currentPath.addLine(to: p4)
        currentPath.closeSubpath()
    }
    
    private func addTexturedStroke(from startPoint: CGPoint, to endPoint: CGPoint) {
        let steps = 20
        for i in 0...steps {
            let t = CGFloat(i) / CGFloat(steps)
            let x = startPoint.x + (endPoint.x - startPoint.x) * t
            let y = startPoint.y + (endPoint.y - startPoint.y) * t
            
            // Add texture variation
            let noiseX = CGFloat.random(in: -2...2)
            let noiseY = CGFloat.random(in: -2...2)
            
            let point = CGPoint(x: x + noiseX, y: y + noiseY)
            
            if i == 0 {
                currentPath.move(to: point)
            } else {
                currentPath.addLine(to: point)
            }
        }
    }
    
    private func eraseAtPoint(_ location: CGPoint) {
        let eraseRadius = drawingManager.currentTool.strokeWidth
        drawingManager.eraseAtPoint(location, radius: eraseRadius)
    }
    
    private func smudgeAtPoint(_ location: CGPoint) {
        // Implement smudge effect
        drawingManager.smudgeAtPoint(location, radius: drawingManager.currentTool.strokeWidth)
    }
    
    // MARK: - Animation Functions
    private func toggleAnimation() {
        isAnimating.toggle()
        
        if isAnimating {
            animationTimer = Timer.scheduledTimer(withTimeInterval: 1.0/30.0, repeats: true) { _ in
                animationFrame += 1
                drawingManager.updateParticles()
            }
        } else {
            animationTimer?.invalidate()
            animationTimer = nil
        }
    }
    
    private func nextFrame() {
        animationFrame += 1
        drawingManager.updateParticles()
    }
    
    private func previousFrame() {
        if animationFrame > 0 {
            animationFrame -= 1
        }
    }
    
    // MARK: - Canvas Functions
    private func resetCanvas() {
        canvasScale = 1.0
        canvasOffset = .zero
        animationFrame = 0
    }
    
    // MARK: - Export Functions
    private func exportImage(format: ExportFormat) {
        // Implementation for image export
        print("Exporting as \(format)")
    }
    
    private func exportAnimation() {
        // Implementation for GIF export
        print("Exporting animation as GIF")
    }
    
    private func exportVideo() {
        // Implementation for video export
        print("Exporting as video")
    }
}

// MARK: - Drawing Manager
class DrawingManager: ObservableObject {
    @Published var layers: [DrawingLayer] = [DrawingLayer(name: "Layer 1")]
    @Published var currentLayerIndex = 0
    @Published var currentTool = DrawingTool()
    @Published var backgroundColor = Color.black
    @Published var history: [HistoryEntry] = []
    @Published var particleEffects: [ParticleEffect] = []
    
    private var historyIndex = -1
    private let maxHistorySize = 50
    
    var currentLayer: DrawingLayer {
        get { layers[currentLayerIndex] }
        set { layers[currentLayerIndex] = newValue }
    }
    
    func addLayer() {
        let newLayer = DrawingLayer(name: "Layer \(layers.count + 1)")
        layers.append(newLayer)
        currentLayerIndex = layers.count - 1
        saveToHistory("Add Layer")
    }
    
    func selectLayer(_ index: Int) {
        currentLayerIndex = index
    }
    
    func toggleLayerVisibility(_ index: Int) {
        layers[index].isVisible.toggle()
    }
    
    func addPath(_ path: ShadowPath) {
        currentLayer.paths.append(path)
    }
    
    func selectTool(_ toolType: ToolType) {
        currentTool.type = toolType
        
        // Apply tool-specific defaults
        switch toolType {
        case .spray:
            currentTool.sprayRadius = 20
            currentTool.sprayDensity = 10
        case .glow:
            currentTool.shadowSettings.layers[0].radius = 15
            currentTool.shadowSettings.layers[0].color = .white
        case .neon:
            currentTool.shadowSettings.layers[0].radius = 20
            currentTool.shadowSettings.layers[0].color = .cyan
        case .lightning:
            currentTool.strokeWidth = 2
        default:
            break
        }
    }
    
    func addShadowLayer() {
        let newLayer = ShadowLayer(
            color: .black,
            radius: 10,
            offsetX: 5,
            offsetY: 5,
            opacity: 0.8
        )
        currentTool.shadowSettings.layers.append(newLayer)
    }
    
    func removeShadowLayer(_ index: Int) {
        if currentTool.shadowSettings.layers.count > 1 {
            currentTool.shadowSettings.layers.remove(at: index)
        }
    }
    
    func updateShadowLayer(_ index: Int, color: Color? = nil, radius: Double? = nil, offsetX: Double? = nil, offsetY: Double? = nil, opacity: Double? = nil) {
        if let color = color {
            currentTool.shadowSettings.layers[index].color = color
        }
        if let radius = radius {
            currentTool.shadowSettings.layers[index].radius = radius
        }
        if let offsetX = offsetX {
            currentTool.shadowSettings.layers[index].offsetX = offsetX
        }
        if let offsetY = offsetY {
            currentTool.shadowSettings.layers[index].offsetY = offsetY
        }
        if let opacity = opacity {
            currentTool.shadowSettings.layers[index].opacity = opacity
        }
    }
    
    func applyShadowPreset(_ preset: ShadowPreset) {
        currentTool.shadowSettings = preset.shadowSettings
    }
    
    func setTexture(_ texture: TextureType) {
        currentTool.textureSettings.type = texture
    }
    
    func setAnimation(_ animation: AnimationType) {
        currentTool.animationSettings.type = animation
    }
    
    func setGradient(_ gradient: GradientType) {
        // Implementation for gradient strokes
    }
    
    func applyBrushPreset(_ preset: BrushPreset) {
        currentTool = preset.tool
    }
    
    func addParticleEffect(_ type: ParticleType) {
        let effect = ParticleEffect(type: type, particles: [])
        particleEffects.append(effect)
    }
    
    func addParticleAt(_ location: CGPoint, type: ParticleType) {
        for i in 0..<particleEffects.count {
            if particleEffects[i].type == type {
                let particle = Particle(
                    x: location.x,
                    y: location.y,
                    size: CGFloat.random(in: 2...8),
                    color: type.color,
                    alpha: 1.0,
                    velocity: CGPoint(
                        x: CGFloat.random(in: -5...5),
                        y: CGFloat.random(in: -5...5)
                    ),
                    life: 1.0
                )
                particleEffects[i].particles.append(particle)
            }
        }
    }
    
    func updateParticles() {
        for i in 0..<particleEffects.count {
            for j in (0..<particleEffects[i].particles.count).reversed() {
                var particle = particleEffects[i].particles[j]
                
                // Update particle properties
                particle.x += particle.velocity.x
                particle.y += particle.velocity.y
                particle.alpha *= 0.98
                particle.life -= 0.016
                
                if particle.life <= 0 || particle.alpha < 0.01 {
                    particleEffects[i].particles.remove(at: j)
                } else {
                    particleEffects[i].particles[j] = particle
                }
            }
        }
    }
    
    func eraseAtPoint(_ location: CGPoint, radius: CGFloat) {
        // Implementation for eraser tool
        for layerIndex in 0..<layers.count {
            for pathIndex in (0..<layers[layerIndex].paths.count).reversed() {
                // Check if path intersects with erase area
                // This is simplified - real implementation would need path intersection
                // Remove path if it intersects
            }
        }
    }
    
    func smudgeAtPoint(_ location: CGPoint, radius: CGFloat) {
        // Implementation for smudge tool
        // This would involve complex path manipulation
    }
    
    func clearAll() {
        for i in 0..<layers.count {
            layers[i].paths.removeAll()
        }
        particleEffects.removeAll()
        saveToHistory("Clear All")
    }
    
    func undo() {
        if historyIndex >= 0 {
            historyIndex -= 1
            if historyIndex >= 0 {
                restoreFromHistory(historyIndex)
            }
        }
    }
    
    func redo() {
        if historyIndex < history.count - 1 {
            historyIndex += 1
            restoreFromHistory(historyIndex)
        }
    }
    
    func saveToHistory(_ description: String) {
        let entry = HistoryEntry(
            description: description,
            layers: layers,
            timestamp: Date()
        )
        
        // Remove future history if we're not at the end
        if historyIndex < history.count - 1 {
            history.removeSubrange((historyIndex + 1)...)
        }
        
        history.append(entry)
        historyIndex = history.count - 1
        
        // Limit history size
        if history.count > maxHistorySize {
            history.removeFirst()
            historyIndex -= 1
        }
    }
    
    func restoreFromHistory(_ index: Int) {
        guard index >= 0 && index < history.count else { return }
        layers = history[index].layers
        historyIndex = index
    }
}

// MARK: - Data Models
struct DrawingLayer {
    var name: String
    var paths: [ShadowPath] = []
    var isVisible = true
    var opacity: Double = 1.0
    var blendMode: BlendMode = .normal
}

struct ShadowPath {
    let path: Path
    let strokeColor: Color
    let strokeWidth: Double
    let shadowSettings: ShadowSettings
    let textureSettings: TextureSettings
    let animationSettings: AnimationSettings
    let lineCap: LineCap
    let lineJoin: LineJoin
    let opacity: Double
}

struct DrawingTool {
    var type: ToolType = .brush
    var strokeColor: Color = .white
    var strokeWidth: Double = 5
    var opacity: Double = 1.0
    var shadowSettings = ShadowSettings()
    var textureSettings = TextureSettings()
    var animationSettings = AnimationSettings()
    var lineCap: LineCap = .round
    var lineJoin: LineJoin = .round
    var sprayRadius: CGFloat = 20
    var sprayDensity: Int = 10
    var hasParticleEffect: Bool = false
    var particleType: ParticleType = .sparkles
}

struct ShadowSettings {
    var layers: [ShadowLayer] = [ShadowLayer()]
    var isEnabled = true
    var dynamicShadows = false
    var lightSource = CGPoint(x: 0.5, y: 0.3) // Normalized coordinates
    var ambientLight: Double = 0.2
    var shadowStrength: Double = 1.0
    var volumetricShadows = false
    var shadowAnimation: ShadowAnimation = .none
}

struct ShadowLayer {
    var color: Color = .black
    var radius: Double = 10
    var offsetX: Double = 5
    var offsetY: Double = 5
    var opacity: Double = 0.8
    var angle: Double = 45 // Shadow direction in degrees
    var distance: Double = 10 // Distance from object
    var softness: Double = 1.0 // Edge softness multiplier
    var density: Double = 1.0 // Shadow density
    var waveform: ShadowWaveform = .none
    var waveIntensity: Double = 0.0
    var innerShadow = false
    var gradientStart: Color = .black
    var gradientEnd: Color = .clear
    var useGradient = false
}

struct TextureSettings {
    var type: TextureType = .smooth
    var intensity: Double = 1.0
    var scale: Double = 1.0
}

struct AnimationSettings {
    var type: AnimationType = .none
    var duration: Double = 1.0
    var delay: Double = 0.0
}

struct ParticleEffect {
    let type: ParticleType
    var particles: [Particle]
}

struct Particle {
    var x: CGFloat
    var y: CGFloat
    var size: CGFloat
    var color: Color
    var alpha: Double
    var velocity: CGPoint
    var life: Double
}

struct HistoryEntry {
    let description: String
    let layers: [DrawingLayer]
    let timestamp: Date
}

// MARK: - Enums
enum ControlPanel: String, CaseIterable {
    case tools = "Tools"
    case shadows = "Shadows"
    case effects = "Effects"
    case colors = "Colors"
    case brushes = "Brushes"
    
    var icon: String {
        switch self {
        case .tools: return "paintbrush"
        case .shadows: return "shadow"
        case .effects: return "sparkles"
        case .colors: return "paintpalette"
        case .brushes: return "scribble.variable"
        }
    }
    
    var title: String { rawValue }
}

enum ToolType: String, CaseIterable {
    case brush = "Brush"
    case pen = "Pen"
    case spray = "Spray"
    case glow = "Glow"
    case neon = "Neon"
    case lightning = "Lightning"
    case calligraphy = "Calligraphy"
    case texture = "Texture"
    case eraser = "Eraser"
    case smudge = "Smudge"
    case pan = "Pan"
    
    var name: String { rawValue }
    
    var icon: String {
        switch self {
        case .brush: return "paintbrush"
        case .pen: return "pencil"
        case .spray: return "spray"
        case .glow: return "circle.dashed"
        case .neon: return "bolt.circle"
        case .lightning: return "bolt"
        case .calligraphy: return "character.cursor.ibeam"
        case .texture: return "scribble.variable"
        case .eraser: return "eraser"
        case .smudge: return "hand.draw"
        case .pan: return "hand.raised"
        }
    }
}

enum ShadowPreset: CaseIterable {
    case softGlow
    case hardDrop
    case neonBlue
    case neonPink
    case fire
    case ice
    case dramatic
    case embossed
    case floating
    case multiLayer
    case volumetricBeam
    case electricStorm
    case prismRefraction
    case quantumGlow
    case morphingShadow
    case holographicShift
    case chromaticAberration
    case galaxyTrail
    case liquidMetal
    case crystalline
    
    var name: String {
        switch self {
        case .softGlow: return "Soft Glow"
        case .hardDrop: return "Hard Drop"
        case .neonBlue: return "Neon Blue"
        case .neonPink: return "Neon Pink"
        case .fire: return "Fire"
        case .ice: return "Ice"
        case .dramatic: return "Dramatic"
        case .embossed: return "Embossed"
        case .floating: return "Floating"
        case .multiLayer: return "Multi-Layer"
        case .volumetricBeam: return "Volumetric Beam"
        case .electricStorm: return "Electric Storm"
        case .prismRefraction: return "Prism Refraction"
        case .quantumGlow: return "Quantum Glow"
        case .morphingShadow: return "Morphing Shadow"
        case .holographicShift: return "Holographic Shift"
        case .chromaticAberration: return "Chromatic Aberration"
        case .galaxyTrail: return "Galaxy Trail"
        case .liquidMetal: return "Liquid Metal"
        case .crystalline: return "Crystalline"
        }
    }
    
    var shadowSettings: ShadowSettings {
        var settings = ShadowSettings()
        
        switch self {
        case .softGlow:
            settings.layers = [ShadowLayer(color: .white, radius: 15, offsetX: 0, offsetY: 0, opacity: 0.8)]
        case .hardDrop:
            settings.layers = [ShadowLayer(color: .black, radius: 0, offsetX: 3, offsetY: 3, opacity: 1.0)]
        case .neonBlue:
            settings.layers = [ShadowLayer(color: .cyan, radius: 20, offsetX: 0, offsetY: 0, opacity: 0.9)]
        case .neonPink:
            settings.layers = [ShadowLayer(color: .pink, radius: 20, offsetX: 0, offsetY: 0, opacity: 0.9)]
        case .fire:
            settings.layers = [
                ShadowLayer(color: .red, radius: 15, offsetX: 0, offsetY: 0, opacity: 0.8),
                ShadowLayer(color: .orange, radius: 25, offsetX: 0, offsetY: 0, opacity: 0.6)
            ]
        case .ice:
            settings.layers = [
                ShadowLayer(color: .blue, radius: 10, offsetX: 0, offsetY: 0, opacity: 0.7),
                ShadowLayer(color: .white, radius: 20, offsetX: 0, offsetY: 0, opacity: 0.5)
            ]
        case .dramatic:
            settings.layers = [ShadowLayer(color: .black, radius: 25, offsetX: 10, offsetY: 10, opacity: 0.8)]
        case .embossed:
            settings.layers = [
                ShadowLayer(color: .white, radius: 2, offsetX: -1, offsetY: -1, opacity: 0.5),
                ShadowLayer(color: .black, radius: 2, offsetX: 1, offsetY: 1, opacity: 0.5)
            ]
        case .floating:
            settings.layers = [ShadowLayer(color: .blue, radius: 10, offsetX: 0, offsetY: 8, opacity: 0.6)]
        case .multiLayer:
            settings.layers = [
                ShadowLayer(color: .red, radius: 5, offsetX: 2, offsetY: 2, opacity: 0.8),
                ShadowLayer(color: .green, radius: 10, offsetX: 4, offsetY: 4, opacity: 0.6),
                ShadowLayer(color: .blue, radius: 15, offsetX: 6, offsetY: 6, opacity: 0.4)
            ]
        case .volumetricBeam:
            settings.volumetricShadows = true
            settings.lightSource = CGPoint(x: 0.2, y: 0.2)
            settings.layers = [
                ShadowLayer(color: .white, radius: 30, offsetX: 15, offsetY: 15, opacity: 0.3, angle: 45, distance: 20, softness: 2.0),
                ShadowLayer(color: .cyan, radius: 20, offsetX: 10, offsetY: 10, opacity: 0.5, angle: 45, distance: 15, softness: 1.5)
            ]
        case .electricStorm:
            settings.shadowAnimation = .lightning
            settings.layers = [
                ShadowLayer(color: .purple, radius: 25, offsetX: 0, offsetY: 0, opacity: 0.8, waveform: .lightning, waveIntensity: 1.0),
                ShadowLayer(color: .blue, radius: 15, offsetX: 0, offsetY: 0, opacity: 0.6, waveform: .zigzag, waveIntensity: 0.8)
            ]
        case .prismRefraction:
            settings.layers = [
                ShadowLayer(color: .red, radius: 8, offsetX: -3, offsetY: -1, opacity: 0.6, gradientStart: .red, gradientEnd: .clear, useGradient: true),
                ShadowLayer(color: .green, radius: 8, offsetX: 0, offsetY: 0, opacity: 0.6, gradientStart: .green, gradientEnd: .clear, useGradient: true),
                ShadowLayer(color: .blue, radius: 8, offsetX: 3, offsetY: 1, opacity: 0.6, gradientStart: .blue, gradientEnd: .clear, useGradient: true)
            ]
        case .quantumGlow:
            settings.shadowAnimation = .quantumFlicker
            settings.layers = [
                ShadowLayer(color: .cyan, radius: 20, offsetX: 0, offsetY: 0, opacity: 0.9, waveform: .quantum, waveIntensity: 1.2),
                ShadowLayer(color: Color(UIColor.magenta), radius: 35, offsetX: 0, offsetY: 0, opacity: 0.4, waveform: .quantum, waveIntensity: 0.8)
            ]
        case .morphingShadow:
            settings.shadowAnimation = .morph
            settings.layers = [
                ShadowLayer(color: .purple, radius: 15, offsetX: 5, offsetY: 5, opacity: 0.7, waveform: .sine, waveIntensity: 1.0)
            ]
        case .holographicShift:
            settings.layers = [
                ShadowLayer(color: .cyan, radius: 12, offsetX: -2, offsetY: 0, opacity: 0.4),
                ShadowLayer(color: Color(UIColor.magenta), radius: 12, offsetX: 2, offsetY: 0, opacity: 0.4),
                ShadowLayer(color: .yellow, radius: 12, offsetX: 0, offsetY: -2, opacity: 0.3)
            ]
        case .chromaticAberration:
            settings.layers = [
                ShadowLayer(color: .red, radius: 5, offsetX: -2, offsetY: 0, opacity: 0.5),
                ShadowLayer(color: .blue, radius: 5, offsetX: 2, offsetY: 0, opacity: 0.5)
            ]
        case .galaxyTrail:
            settings.shadowAnimation = .spiral
            settings.layers = [
                ShadowLayer(color: .purple, radius: 25, offsetX: 0, offsetY: 0, opacity: 0.8, gradientStart: .purple, gradientEnd: .clear, useGradient: true),
                ShadowLayer(color: .blue, radius: 40, offsetX: 0, offsetY: 0, opacity: 0.4, gradientStart: .blue, gradientEnd: .clear, useGradient: true)
            ]
        case .liquidMetal:
            settings.layers = [
                ShadowLayer(color: .gray, radius: 15, offsetX: 3, offsetY: 6, opacity: 0.9, softness: 0.5),
                ShadowLayer(color: .white, radius: 8, offsetX: 1, offsetY: 2, opacity: 0.3, innerShadow: true)
            ]
        case .crystalline:
            settings.layers = [
                ShadowLayer(color: .cyan, radius: 3, offsetX: 2, offsetY: 2, opacity: 0.8, softness: 0.2),
                ShadowLayer(color: .blue, radius: 6, offsetX: 4, offsetY: 4, opacity: 0.6, softness: 0.3),
                ShadowLayer(color: .white, radius: 12, offsetX: 8, offsetY: 8, opacity: 0.3, softness: 1.0)
            ]
        }
        
        return settings
    }
}

enum TextureType: String, CaseIterable {
    case smooth = "Smooth"
    case rough = "Rough"
    case canvas = "Canvas"
    case paper = "Paper"
    case metal = "Metal"
    case fabric = "Fabric"
    
    var name: String { rawValue }
    
    var icon: String {
        switch self {
        case .smooth: return "circle.fill"
        case .rough: return "scribble"
        case .canvas: return "grid"
        case .paper: return "doc"
        case .metal: return "sparkles"
        case .fabric: return "waveform"
        }
    }
}

enum AnimationType: String, CaseIterable {
    case none = "None"
    case pulse = "Pulse"
    case glow = "Glow"
    case flicker = "Flicker"
    case wave = "Wave"
    case rotate = "Rotate"
    case scale = "Scale"
    case fade = "Fade"
    
    var name: String { rawValue }
    
    var icon: String {
        switch self {
        case .none: return "stop"
        case .pulse: return "heart"
        case .glow: return "sun.max"
        case .flicker: return "bolt"
        case .wave: return "waveform"
        case .rotate: return "arrow.clockwise"
        case .scale: return "plus.magnifyingglass"
        case .fade: return "eye.slash"
        }
    }
}

enum ParticleType: CaseIterable {
    case sparkles
    case fire
    case snow
    case magic
    case stars
    case bubbles
    
    var color: Color {
        switch self {
        case .sparkles: return .yellow
        case .fire: return .orange
        case .snow: return .white
        case .magic: return .purple
        case .stars: return .cyan
        case .bubbles: return .blue
        }
    }
}

enum LineCap: String, CaseIterable {
    case butt = "Butt"
    case round = "Round"
    case square = "Square"
    
    var name: String { rawValue }
    
    var cgLineCap: CGLineCap {
        switch self {
        case .butt: return .butt
        case .round: return .round
        case .square: return .square
        }
    }
}

enum LineJoin: String, CaseIterable {
    case miter = "Miter"
    case round = "Round"
    case bevel = "Bevel"
    
    var name: String { rawValue }
    
    var cgLineJoin: CGLineJoin {
        switch self {
        case .miter: return .miter
        case .round: return .round
        case .bevel: return .bevel
        }
    }
}

enum BlendMode: String, CaseIterable {
    case normal = "Normal"
    case multiply = "Multiply"
    case screen = "Screen"
    case overlay = "Overlay"
    case softLight = "Soft Light"
    case hardLight = "Hard Light"
    case colorDodge = "Color Dodge"
    case colorBurn = "Color Burn"
    case darken = "Darken"
    case lighten = "Lighten"
    case difference = "Difference"
    case exclusion = "Exclusion"
    
    var swiftUIBlendMode: SwiftUI.BlendMode {
        switch self {
        case .normal: return .normal
        case .multiply: return .multiply
        case .screen: return .screen
        case .overlay: return .overlay
        case .softLight: return .softLight
        case .hardLight: return .hardLight
        case .colorDodge: return .colorDodge
        case .colorBurn: return .colorBurn
        case .darken: return .darken
        case .lighten: return .lighten
        case .difference: return .difference
        case .exclusion: return .exclusion
        }
    }
}

enum GradientType: CaseIterable {
    case sunset
    case ocean
    case fire
    case rainbow
    case neon
    case metal
    
    var name: String {
        switch self {
        case .sunset: return "Sunset"
        case .ocean: return "Ocean"
        case .fire: return "Fire"
        case .rainbow: return "Rainbow"
        case .neon: return "Neon"
        case .metal: return "Metal"
        }
    }
    
    var gradient: LinearGradient {
        switch self {
        case .sunset:
            return LinearGradient(colors: [.orange, .red, .purple], startPoint: .leading, endPoint: .trailing)
        case .ocean:
            return LinearGradient(colors: [.blue, .cyan, .teal], startPoint: .leading, endPoint: .trailing)
        case .fire:
            return LinearGradient(colors: [.red, .orange, .yellow], startPoint: .leading, endPoint: .trailing)
        case .rainbow:
            return LinearGradient(colors: [.red, .orange, .yellow, .green, .blue, .purple], startPoint: .leading, endPoint: .trailing)
        case .neon:
            return LinearGradient(colors: [.pink, .cyan], startPoint: .leading, endPoint: .trailing)
        case .metal:
            return LinearGradient(colors: [.gray, .white, .gray], startPoint: .leading, endPoint: .trailing)
        }
    }
}

enum BrushPreset: CaseIterable {
    case fine
    case bold
    case artistic
    case technical
    case expressive
    case delicate
    
    var name: String {
        switch self {
        case .fine: return "Fine"
        case .bold: return "Bold"
        case .artistic: return "Artistic"
        case .technical: return "Technical"
        case .expressive: return "Expressive"
        case .delicate: return "Delicate"
        }
    }
    
    var icon: String {
        switch self {
        case .fine: return "pencil.tip"
        case .bold: return "paintbrush.pointed.fill"
        case .artistic: return "paintbrush.fill"
        case .technical: return "ruler"
        case .expressive: return "scribble.variable"
        case .delicate: return "pencil.tip.crop.circle"
        }
    }
    
    var tool: DrawingTool {
        var tool = DrawingTool()
        
        switch self {
        case .fine:
            tool.strokeWidth = 1
            tool.type = .pen
            tool.lineCap = .round
        case .bold:
            tool.strokeWidth = 20
            tool.type = .brush
            tool.lineCap = .round
        case .artistic:
            tool.strokeWidth = 10
            tool.type = .brush
            tool.textureSettings.type = .canvas
        case .technical:
            tool.strokeWidth = 2
            tool.type = .pen
            tool.lineCap = .square
            tool.lineJoin = .miter
        case .expressive:
            tool.strokeWidth = 15
            tool.type = .calligraphy
            tool.opacity = 0.8
        case .delicate:
            tool.strokeWidth = 3
            tool.type = .brush
            tool.opacity = 0.6
        }
        
        return tool
    }
}

enum ExportFormat {
    case png
    case svg
    case gif
    case video
}

// MARK: - Color Palette
struct ColorPalette {
    static let defaultColors: [Color] = [
        .white, .black, .gray, .red,
        .orange, .yellow, .green, .blue,
        .purple, .pink, .cyan, .brown,
        Color(.sRGB, red: 1.0, green: 0.0, blue: 0.5), // Hot pink
        Color(.sRGB, red: 0.0, green: 1.0, blue: 0.5), // Spring green
        Color(.sRGB, red: 0.5, green: 0.0, blue: 1.0), // Electric purple
        Color(.sRGB, red: 1.0, green: 0.5, blue: 0.0)  // Electric orange
    ]
}

// MARK: - View Modifiers
struct ShadowEffectModifier: ViewModifier {
    let shadowSettings: ShadowSettings
    
    func body(content: Content) -> some View {
        var modifiedContent = AnyView(content)
        
        for layer in shadowSettings.layers {
            modifiedContent = AnyView(
                modifiedContent
                    .shadow(
                        color: layer.color.opacity(layer.opacity),
                        radius: layer.radius,
                        x: layer.offsetX,
                        y: layer.offsetY
                    )
            )
        }
        
        return modifiedContent
    }
}

struct TextureEffectModifier: ViewModifier {
    let textureSettings: TextureSettings
    
    func body(content: Content) -> some View {
        switch textureSettings.type {
        case .smooth:
            return AnyView(content)
        case .rough:
            return AnyView(
                content
                    .overlay(
                        Rectangle()
                            .fill(Color.white.opacity(0.1))
                            .blendMode(.overlay)
                    )
            )
        case .canvas:
            return AnyView(
                content
                    .overlay(
                        Canvas { context, size in
                            for x in stride(from: 0, through: size.width, by: 2) {
                                for y in stride(from: 0, through: size.height, by: 2) {
                                    if Bool.random() {
                                        context.fill(
                                            Path(CGRect(x: x, y: y, width: 1, height: 1)),
                                            with: .color(.white.opacity(0.1))
                                        )
                                    }
                                }
                            }
                        }
                        .blendMode(.overlay)
                    )
            )
        case .paper:
            return AnyView(
                content
                    .overlay(
                        LinearGradient(
                            colors: [Color.white.opacity(0.05), Color.clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        .blendMode(.overlay)
                    )
            )
        case .metal:
            return AnyView(
                content
                    .overlay(
                        LinearGradient(
                            colors: [Color.white.opacity(0.3), Color.clear, Color.white.opacity(0.2)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .blendMode(.overlay)
                    )
            )
        case .fabric:
            return AnyView(
                content
                    .overlay(
                        Rectangle()
                            .fill(Color.gray.opacity(0.1))
                            .blendMode(.multiply)
                    )
            )
        }
    }
}

struct AnimationEffectModifier: ViewModifier {
    let animationSettings: AnimationSettings
    let frame: Int
    
    func body(content: Content) -> some View {
        switch animationSettings.type {
        case .none:
            return AnyView(content)
        case .pulse:
            let scale = 1.0 + 0.2 * sin(Double(frame) * 0.2)
            return AnyView(content.scaleEffect(scale))
        case .glow:
            let opacity = 0.5 + 0.5 * sin(Double(frame) * 0.3)
            return AnyView(content.opacity(opacity))
        case .flicker:
            let opacity = Bool.random() ? 1.0 : 0.3
            return AnyView(content.opacity(opacity))
        case .wave:
            let offset = 10 * sin(Double(frame) * 0.1)
            return AnyView(content.offset(y: offset))
        case .rotate:
            let rotation = Double(frame) * 2.0
            return AnyView(content.rotationEffect(.degrees(rotation)))
        case .scale:
            let scale = 1.0 + 0.3 * sin(Double(frame) * 0.15)
            return AnyView(content.scaleEffect(scale))
        case .fade:
            let opacity = 0.3 + 0.7 * abs(sin(Double(frame) * 0.1))
            return AnyView(content.opacity(opacity))
        }
    }
}

struct ShadowPresetModifier: ViewModifier {
    let preset: ShadowPreset
    
    func body(content: Content) -> some View {
        var modifiedContent = AnyView(content)
        
        for layer in preset.shadowSettings.layers {
            modifiedContent = AnyView(
                modifiedContent
                    .shadow(
                        color: layer.color.opacity(layer.opacity),
                        radius: layer.radius,
                        x: layer.offsetX,
                        y: layer.offsetY
                    )
            )
        }
        
        return modifiedContent
    }
}

// MARK: - Button Styles
struct EffectButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.cyan.opacity(configuration.isPressed ? 0.8 : 0.3))
            )
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct AnimationButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.green.opacity(configuration.isPressed ? 0.8 : 0.3))
            )
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct ExportButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.purple.opacity(configuration.isPressed ? 0.8 : 0.3))
            )
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - View Extensions
extension View {
    func applyShadowEffect(_ settings: ShadowSettings) -> some View {
        modifier(ShadowEffectModifier(shadowSettings: settings))
    }
    
    func applyTextureEffect(_ settings: TextureSettings) -> some View {
        modifier(TextureEffectModifier(textureSettings: settings))
    }
    
    func applyAnimationEffect(_ settings: AnimationSettings, frame: Int) -> some View {
        modifier(AnimationEffectModifier(animationSettings: settings, frame: frame))
    }
    
    func applyShadowPreset(_ preset: ShadowPreset) -> some View {
        modifier(ShadowPresetModifier(preset: preset))
    }
}

// MARK: - Additional Helper Functions
extension DrawingManager {
    func duplicate(_ layerIndex: Int) {
        guard layerIndex < layers.count else { return }
        let originalLayer = layers[layerIndex]
        var newLayer = DrawingLayer(name: "\(originalLayer.name) Copy")
        newLayer.paths = originalLayer.paths
        newLayer.opacity = originalLayer.opacity
        newLayer.blendMode = originalLayer.blendMode
        layers.insert(newLayer, at: layerIndex + 1)
        saveToHistory("Duplicate Layer")
    }
    
    func mergeDown(_ layerIndex: Int) {
        guard layerIndex > 0 && layerIndex < layers.count else { return }
        layers[layerIndex - 1].paths.append(contentsOf: layers[layerIndex].paths)
        layers.remove(at: layerIndex)
        if currentLayerIndex >= layerIndex {
            currentLayerIndex = max(0, currentLayerIndex - 1)
        }
        saveToHistory("Merge Layer Down")
    }
    
    func deleteLayer(_ layerIndex: Int) {
        guard layers.count > 1 && layerIndex < layers.count else { return }
        layers.remove(at: layerIndex)
        if currentLayerIndex >= layerIndex {
            currentLayerIndex = max(0, currentLayerIndex - 1)
        }
        saveToHistory("Delete Layer")
    }
    
    func moveLayer(from sourceIndex: Int, to destinationIndex: Int) {
        guard sourceIndex != destinationIndex &&
              sourceIndex < layers.count &&
              destinationIndex < layers.count else { return }
        
        let layer = layers.remove(at: sourceIndex)
        layers.insert(layer, at: destinationIndex)
        
        // Update current layer index
        if currentLayerIndex == sourceIndex {
            currentLayerIndex = destinationIndex
        } else if sourceIndex < currentLayerIndex && destinationIndex >= currentLayerIndex {
            currentLayerIndex -= 1
        } else if sourceIndex > currentLayerIndex && destinationIndex <= currentLayerIndex {
            currentLayerIndex += 1
        }
        
        saveToHistory("Move Layer")
    }
    
    func setLayerOpacity(_ layerIndex: Int, opacity: Double) {
        guard layerIndex < layers.count else { return }
        layers[layerIndex].opacity = opacity
    }
    
    func setLayerBlendMode(_ layerIndex: Int, blendMode: BlendMode) {
        guard layerIndex < layers.count else { return }
        layers[layerIndex].blendMode = blendMode
    }
    
    func renameLayer(_ layerIndex: Int, name: String) {
        guard layerIndex < layers.count else { return }
        layers[layerIndex].name = name
    }
}

// MARK: - Canvas Utilities
struct CanvasUtilities {
    static func createGrid(size: CGSize, spacing: CGFloat, color: Color, lineWidth: CGFloat) -> Path {
        var path = Path()
        
        for x in stride(from: 0, through: size.width, by: spacing) {
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: size.height))
        }
        
        for y in stride(from: 0, through: size.height, by: spacing) {
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: size.width, y: y))
        }
        
        return path
    }
    
    static func calculatePathBounds(_ path: Path) -> CGRect {
        // This would need proper implementation for path bounds calculation
        return CGRect(x: 0, y: 0, width: 100, height: 100)
    }
    
    static func simplifyPath(_ path: Path, tolerance: CGFloat) -> Path {
        // Implementation for path simplification to reduce points
        return path
    }
}

// MARK: - Math Utilities
struct MathUtilities {
    static func distance(from point1: CGPoint, to point2: CGPoint) -> CGFloat {
        let dx = point2.x - point1.x
        let dy = point2.y - point1.y
        return sqrt(dx * dx + dy * dy)
    }
    
    static func angle(from point1: CGPoint, to point2: CGPoint) -> Double {
        let dx = point2.x - point1.x
        let dy = point2.y - point1.y
        return atan2(Double(dy), Double(dx))
    }
    
    static func lerp(from start: CGFloat, to end: CGFloat, t: CGFloat) -> CGFloat {
        return start + (end - start) * t
    }
    
    static func smoothstep(_ t: CGFloat) -> CGFloat {
        return t * t * (3 - 2 * t)
    }
}

// MARK: - Performance Optimization
class PerformanceManager {
    private var frameCount = 0
    private var lastFPSUpdate = Date()
    private var currentFPS: Double = 0
    
    func updateFPS() {
        frameCount += 1
        let now = Date()
        let timeDiff = now.timeIntervalSince(lastFPSUpdate)
        
        if timeDiff >= 1.0 {
            currentFPS = Double(frameCount) / timeDiff
            frameCount = 0
            lastFPSUpdate = now
        }
    }
    
    func getCurrentFPS() -> Double {
        return currentFPS
    }
    
    func shouldSkipFrame() -> Bool {
        return currentFPS < 20 // Skip frames if performance is poor
    }
}

// MARK: - File Management
struct FileManager {
    static func saveProject(_ layers: [DrawingLayer], to url: URL) throws {
        // Implementation for saving project to file
        let encoder = JSONEncoder()
        // This would need proper encoding implementation
    }
    
    static func loadProject(from url: URL) throws -> [DrawingLayer] {
        // Implementation for loading project from file
        let decoder = JSONDecoder()
        // This would need proper decoding implementation
        return []
    }
    
    static func exportImage(_ layers: [DrawingLayer], size: CGSize, format: ExportFormat) -> Data? {
        // Implementation for image export
        return nil
    }
}

// MARK: - Settings Manager
class SettingsManager: ObservableObject {
    @Published var autoSave = true
    @Published var maxHistorySize = 50
    @Published var showPerformanceStats = false
    @Published var enableParticles = true
    @Published var highQualityRendering = true
    @Published var touchSensitivity: Double = 1.0
    @Published var undoLimit = 50
    
    private let userDefaults = UserDefaults.standard
    
    init() {
        loadSettings()
    }
    
    func loadSettings() {
        autoSave = userDefaults.bool(forKey: "autoSave")
        maxHistorySize = userDefaults.integer(forKey: "maxHistorySize")
        showPerformanceStats = userDefaults.bool(forKey: "showPerformanceStats")
        enableParticles = userDefaults.bool(forKey: "enableParticles")
        highQualityRendering = userDefaults.bool(forKey: "highQualityRendering")
        touchSensitivity = userDefaults.double(forKey: "touchSensitivity")
        undoLimit = userDefaults.integer(forKey: "undoLimit")
    }
    
    func saveSettings() {
        userDefaults.set(autoSave, forKey: "autoSave")
        userDefaults.set(maxHistorySize, forKey: "maxHistorySize")
        userDefaults.set(showPerformanceStats, forKey: "showPerformanceStats")
        userDefaults.set(enableParticles, forKey: "enableParticles")
        userDefaults.set(highQualityRendering, forKey: "highQualityRendering")
        userDefaults.set(touchSensitivity, forKey: "touchSensitivity")
        userDefaults.set(undoLimit, forKey: "undoLimit")
    }
}

// MARK: - Advanced Brush Engine
struct BrushEngine {
    static func calculatePressure(_ location: CGPoint, previousLocation: CGPoint?, velocity: CGFloat) -> CGFloat {
        guard let prevLoc = previousLocation else { return 1.0 }
        
        let distance = MathUtilities.distance(from: prevLoc, to: location)
        let normalizedVelocity = min(1.0, velocity / 100.0)
        
        // Simulate pressure based on drawing speed
        return 1.0 - (normalizedVelocity * 0.5)
    }
    
    static func smoothPath(_ points: [CGPoint], smoothing: CGFloat) -> Path {
        guard points.count > 2 else {
            var path = Path()
            if points.count == 1 {
                path.move(to: points[0])
            } else if points.count == 2 {
                path.move(to: points[0])
                path.addLine(to: points[1])
            }
            return path
        }
        
        var path = Path()
        path.move(to: points[0])
        
        for i in 1..<points.count - 1 {
            let currentPoint = points[i]
            let nextPoint = points[i + 1]
            
            let controlPointX = currentPoint.x + (nextPoint.x - currentPoint.x) * smoothing
            let controlPointY = currentPoint.y + (nextPoint.y - currentPoint.y) * smoothing
            
            path.addQuadCurve(
                to: nextPoint,
                control: CGPoint(x: controlPointX, y: controlPointY)
            )
        }
        
        return path
    }
}

// MARK: - Gesture Recognizers
struct DrawingGestureRecognizer {
    static func recognizeStroke(_ points: [CGPoint]) -> StrokeType {
        guard points.count > 3 else { return .freeform }
        
        let startPoint = points.first!
        let endPoint = points.last!
        let distance = MathUtilities.distance(from: startPoint, to: endPoint)
        
        // Check for circle
        if isCircularStroke(points) {
            return .circle
        }
        
        // Check for straight line
        if isStraightLine(points, tolerance: 20) {
            return .line
        }
        
        // Check for rectangle
        if isRectangularStroke(points) {
            return .rectangle
        }
        
        return .freeform
    }
    
    private static func isCircularStroke(_ points: [CGPoint]) -> Bool {
        // Implementation for circle detection
        return false
    }
    
    private static func isStraightLine(_ points: [CGPoint], tolerance: CGFloat) -> Bool {
        guard points.count > 2 else { return true }
        
        let startPoint = points.first!
        let endPoint = points.last!
        
        for point in points.dropFirst().dropLast() {
            let distanceToLine = distanceFromPointToLine(point, lineStart: startPoint, lineEnd: endPoint)
            if distanceToLine > tolerance {
                return false
            }
        }
        
        return true
    }
    
    private static func isRectangularStroke(_ points: [CGPoint]) -> Bool {
        // Implementation for rectangle detection
        return false
    }
    
    private static func distanceFromPointToLine(_ point: CGPoint, lineStart: CGPoint, lineEnd: CGPoint) -> CGFloat {
        let A = lineEnd.y - lineStart.y
        let B = lineStart.x - lineEnd.x
        let C = lineEnd.x * lineStart.y - lineStart.x * lineEnd.y
        
        return abs(A * point.x + B * point.y + C) / sqrt(A * A + B * B)
    }
}

enum StrokeType {
    case freeform
    case line
    case circle
    case rectangle
    case triangle
}

// MARK: - Color Analysis
struct ColorAnalyzer {
    static func getComplementaryColor(_ color: Color) -> Color {
        // Implementation for complementary color calculation
        return color
    }
    
    static func getAnalogousColors(_ color: Color) -> [Color] {
        // Implementation for analogous colors
        return [color]
    }
    
    static func adjustBrightness(_ color: Color, by amount: Double) -> Color {
        // Implementation for brightness adjustment
        return color
    }
    
    static func adjustSaturation(_ color: Color, by amount: Double) -> Color {
        // Implementation for saturation adjustment
        return color
    }
}

// MARK: - Audio Feedback (Optional)
class AudioManager {
    static let shared = AudioManager()
    
    private init() {}
    
    func playDrawingSound() {
        // Implementation for drawing sound effects
    }
    
    func playUISound(_ soundType: UISoundType) {
        // Implementation for UI sound effects
    }
}

enum UISoundType {
    case buttonTap
    case toolSelect
    case layerCreate
    case undo
    case redo
    case export
}

// MARK: - Accessibility Support
extension View {
    func accessibilityDrawingTool(_ toolName: String) -> some View {
        self.accessibility(label: Text("Drawing tool: \(toolName)"))
            .accessibility(hint: Text("Double tap to select this drawing tool"))
    }
    
    func accessibilityColorPicker(_ colorName: String) -> some View {
        self.accessibility(label: Text("Color: \(colorName)"))
            .accessibility(hint: Text("Double tap to select this color"))
    }
    
    func accessibilitySlider(_ name: String, value: String) -> some View {
        self.accessibility(label: Text("\(name): \(value)"))
            .accessibility(hint: Text("Swipe up or down to adjust"))
    }
}

// MARK: - Error Handling
enum DrawingError: Error {
    case canvasNotReady
    case invalidTool
    case layerNotFound
    case exportFailed
    case importFailed
    case insufficientMemory
}

struct ErrorHandler {
    static func handle(_ error: DrawingError) {
        switch error {
        case .canvasNotReady:
            print("Canvas is not ready for drawing")
        case .invalidTool:
            print("Selected tool is invalid")
        case .layerNotFound:
            print("Specified layer could not be found")
        case .exportFailed:
            print("Failed to export artwork")
        case .importFailed:
            print("Failed to import artwork")
        case .insufficientMemory:
            print("Insufficient memory to complete operation")
        }
    }
}

// MARK: - Advanced Shadow Enums
enum ShadowAnimation: CaseIterable {
    case none
    case pulse
    case flicker
    case wave
    case spiral
    case lightning
    case quantumFlicker
    case morph
    case breathe
    case shimmer
    
    var name: String {
        switch self {
        case .none: return "None"
        case .pulse: return "Pulse"
        case .flicker: return "Flicker"
        case .wave: return "Wave"
        case .spiral: return "Spiral"
        case .lightning: return "Lightning"
        case .quantumFlicker: return "Quantum Flicker"
        case .morph: return "Morph"
        case .breathe: return "Breathe"
        case .shimmer: return "Shimmer"
        }
    }
}

enum ShadowWaveform: CaseIterable {
    case none
    case sine
    case square
    case triangle
    case sawtooth
    case quantum
    case lightning
    case zigzag
    case spiral
    case noise
    
    var name: String {
        switch self {
        case .none: return "None"
        case .sine: return "Sine"
        case .square: return "Square"
        case .triangle: return "Triangle"
        case .sawtooth: return "Sawtooth"
        case .quantum: return "Quantum"
        case .lightning: return "Lightning"
        case .zigzag: return "Zigzag"
        case .spiral: return "Spiral"
        case .noise: return "Noise"
        }
    }
    
    func calculateOffset(time: Double, intensity: Double, baseOffset: CGFloat) -> CGFloat {
        switch self {
        case .none:
            return baseOffset
        case .sine:
            return baseOffset + CGFloat(sin(time) * intensity)
        case .square:
            return baseOffset + CGFloat(sin(time) > 0 ? intensity : -intensity)
        case .triangle:
            return baseOffset + CGFloat(2 * intensity * asin(sin(time)) / .pi)
        case .sawtooth:
            return baseOffset + CGFloat(intensity * (2 * (time / (2 * .pi) - floor(time / (2 * .pi) + 0.5))))
        case .quantum:
            let noise = sin(time * 3.7) * cos(time * 2.3) * sin(time * 5.1)
            return baseOffset + CGFloat(noise * intensity)
        case .lightning:
            let randomFactor = sin(time * 13.7) * cos(time * 7.3)
            return baseOffset + CGFloat(randomFactor * intensity * (Double.random(in: 0.5...1.5)))
        case .zigzag:
            return baseOffset + CGFloat(intensity * ((time.truncatingRemainder(dividingBy: .pi)) < .pi/2 ? 1 : -1))
        case .spiral:
            return baseOffset + CGFloat(sin(time) * cos(time * 0.5) * intensity)
        case .noise:
            return baseOffset + CGFloat((Double.random(in: -1...1)) * intensity)
        }
    }
}

// MARK: - Advanced Shadow Engine
struct AdvancedShadowEngine {
    static func calculateDynamicShadow(
        path: Path, 
        lightSource: CGPoint, 
        settings: ShadowSettings,
        frame: Int
    ) -> [ShadowLayer] {
        var dynamicLayers: [ShadowLayer] = []
        
        for (index, layer) in settings.layers.enumerated() {
            var modifiedLayer = layer
            
            if settings.dynamicShadows {
                // Calculate shadow based on light source position
                let time = Double(frame) * 0.1
                
                // Apply waveform modifications
                if layer.waveform != .none {
                    let newOffsetX = layer.waveform.calculateOffset(
                        time: time, 
                        intensity: layer.waveIntensity * 10, 
                        baseOffset: layer.offsetX
                    )
                    let newOffsetY = layer.waveform.calculateOffset(
                        time: time * 1.3, 
                        intensity: layer.waveIntensity * 10, 
                        baseOffset: layer.offsetY
                    )
                    
                    modifiedLayer.offsetX = newOffsetX
                    modifiedLayer.offsetY = newOffsetY
                }
                
                // Apply shadow animation
                switch settings.shadowAnimation {
                case .pulse:
                    let pulseIntensity = 1.0 + 0.3 * sin(time * 2)
                    modifiedLayer.radius *= pulseIntensity
                    modifiedLayer.opacity *= pulseIntensity
                    
                case .flicker:
                    if Int(time * 10) % 7 == 0 {
                        modifiedLayer.opacity *= 0.3
                    }
                    
                case .wave:
                    let waveOffset = sin(time + Double(index) * 0.5) * 5
                    modifiedLayer.offsetY += waveOffset
                    
                case .spiral:
                    let spiralRadius = 5.0
                    modifiedLayer.offsetX += cos(time + Double(index) * 0.7) * spiralRadius
                    modifiedLayer.offsetY += sin(time + Double(index) * 0.7) * spiralRadius
                    
                case .lightning:
                    if Int(time * 15) % 23 == 0 {
                        modifiedLayer.offsetX += Double.random(in: -10...10)
                        modifiedLayer.offsetY += Double.random(in: -10...10)
                        modifiedLayer.opacity *= 1.5
                    }
                    
                case .quantumFlicker:
                    let quantum = sin(time * 3.7) * cos(time * 2.3) * sin(time * 5.1)
                    modifiedLayer.opacity *= (0.7 + 0.3 * abs(quantum))
                    modifiedLayer.radius *= (0.8 + 0.4 * abs(quantum))
                    
                case .morph:
                    let morphFactor = sin(time * 0.8) * 0.5 + 0.5
                    modifiedLayer.radius = modifiedLayer.radius * (0.5 + morphFactor)
                    modifiedLayer.softness = modifiedLayer.softness * (0.3 + morphFactor * 1.7)
                    
                case .breathe:
                    let breathe = sin(time * 0.5) * 0.3 + 1.0
                    modifiedLayer.radius *= breathe
                    modifiedLayer.opacity *= (breathe * 0.7 + 0.3)
                    
                case .shimmer:
                    let shimmer = sin(time * 4 + Double(index) * 1.2) * 0.2 + 0.8
                    modifiedLayer.opacity *= shimmer
                    
                case .none:
                    break
                }
                
                // Volumetric shadow calculations
                if settings.volumetricShadows {
                    let volumetricIntensity = calculateVolumetricIntensity(
                        lightSource: lightSource,
                        ambientLight: settings.ambientLight
                    )
                    modifiedLayer.radius *= volumetricIntensity
                    modifiedLayer.opacity *= volumetricIntensity
                }
            }
            
            dynamicLayers.append(modifiedLayer)
        }
        
        return dynamicLayers
    }
    
    private static func calculateVolumetricIntensity(lightSource: CGPoint, ambientLight: Double) -> Double {
        // Simulate volumetric lighting effects
        let lightDistance = sqrt(pow(lightSource.x - 0.5, 2) + pow(lightSource.y - 0.5, 2))
        let volumetricFactor = max(0.3, 1.0 - lightDistance)
        return ambientLight + (1.0 - ambientLight) * volumetricFactor
    }
    
    static func createVolumetricBeam(
        from start: CGPoint,
        to end: CGPoint,
        lightSource: CGPoint,
        intensity: Double
    ) -> Path {
        var path = Path()
        
        // Create a volumetric light beam effect
        let beamWidth = 20.0 * intensity
        let segments = 10
        
        for i in 0...segments {
            let t = Double(i) / Double(segments)
            let currentPoint = CGPoint(
                x: start.x + (end.x - start.x) * CGFloat(t),
                y: start.y + (end.y - start.y) * CGFloat(t)
            )
            
            let distanceFromLight = sqrt(
                pow(currentPoint.x - lightSource.x, 2) + 
                pow(currentPoint.y - lightSource.y, 2)
            )
            
            let localWidth = beamWidth * (1.0 - Double(distanceFromLight) * 0.01)
            
            if i == 0 {
                path.move(to: currentPoint)
            } else {
                let rect = CGRect(
                    x: currentPoint.x - CGFloat(localWidth/2),
                    y: currentPoint.y - CGFloat(localWidth/2),
                    width: CGFloat(localWidth),
                    height: CGFloat(localWidth)
                )
                path.addEllipse(in: rect)
            }
        }
        
        return path
    }
}

// MARK: - Enhanced Shadow Modifier
struct EnhancedShadowEffectModifier: ViewModifier {
    let shadowSettings: ShadowSettings
    let animationFrame: Int
    
    func body(content: Content) -> some View {
        let dynamicLayers = AdvancedShadowEngine.calculateDynamicShadow(
            path: Path(), // This would be the actual path in a real implementation
            lightSource: shadowSettings.lightSource,
            settings: shadowSettings,
            frame: animationFrame
        )
        
        var modifiedContent = AnyView(content)
        
        for layer in dynamicLayers {
            if layer.useGradient {
                // Apply gradient shadow
                modifiedContent = AnyView(
                    modifiedContent
                        .overlay(
                            Rectangle()
                                .fill(
                                    RadialGradient(
                                        colors: [layer.gradientStart.opacity(layer.opacity), layer.gradientEnd],
                                        center: .center,
                                        startRadius: 0,
                                        endRadius: layer.radius
                                    )
                                )
                                .offset(x: layer.offsetX, y: layer.offsetY)
                                .blur(radius: layer.radius * layer.softness)
                                .blendMode(.multiply)
                        )
                )
            } else if layer.innerShadow {
                // Apply inner shadow
                modifiedContent = AnyView(
                    modifiedContent
                        .overlay(
                            Rectangle()
                                .fill(layer.color.opacity(layer.opacity))
                                .mask(
                                    content
                                        .blur(radius: layer.radius)
                                        .offset(x: -layer.offsetX, y: -layer.offsetY)
                                )
                                .blendMode(.multiply)
                        )
                )
            } else {
                // Apply standard shadow
                modifiedContent = AnyView(
                    modifiedContent
                        .shadow(
                            color: layer.color.opacity(layer.opacity * layer.density),
                            radius: layer.radius * layer.softness,
                            x: layer.offsetX,
                            y: layer.offsetY
                        )
                )
            }
        }
        
        return modifiedContent
    }
}

// MARK: - Memory Management
class MemoryManager {
    static let shared = MemoryManager()
    
    private init() {}
    
    func optimizeMemory() {
        // Implementation for memory optimization
        clearUnusedPaths()
        compressHistory()
        cleanupParticles()
    }
    
    private func clearUnusedPaths() {
        // Remove paths that are no longer visible or needed
    }
    
    private func compressHistory() {
        // Compress older history entries to save memory
    }
    
    private func cleanupParticles() {
        // Remove expired particle effects
    }
    
    func getMemoryUsage() -> Int {
        // Return current memory usage in bytes
        return 0
    }
}

@main
struct ShadowDrawApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

// MARK: - Preview
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .preferredColorScheme(.dark)
    }
}
