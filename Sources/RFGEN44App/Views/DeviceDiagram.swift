import SwiftUI
import RFGen44Kit

/// Block diagram of the signal path: reference → ADF4351 → RF OUT, with the
/// AUX (Ref/Trigger) function below. Clicking RF OUT toggles the output,
/// like the pictogram in the Qt app.
struct DeviceDiagram: View {
    let referenceMHz: Double
    let aux: AuxFunction
    let rfOn: Bool?
    let isEnabled: Bool
    let toggleRF: () -> Void

    var body: some View {
        Grid(horizontalSpacing: 6, verticalSpacing: 4) {
            GridRow {
                DiagramBox {
                    VStack(spacing: 2) {
                        Text(aux == .externalReference ? "EXT REF" : "INT REF").bold()
                        Text(Format.mhz(referenceMHz)).monospacedDigit()
                    }
                }
                Image(systemName: "arrow.right").foregroundStyle(.secondary)
                DiagramBox {
                    VStack(spacing: 2) {
                        Text("ADF4351").bold()
                        Text("PLL")
                    }
                }
                Image(systemName: "arrow.right").foregroundStyle(.secondary)
                Button(action: toggleRF) {
                    DiagramBox(stroke: rfColor, fill: rfColor.opacity(0.15)) {
                        VStack(spacing: 2) {
                            Text("RF OUT").bold()
                            Text(rfLabel).foregroundStyle(rfColor).bold()
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(!isEnabled)
                .help("Click to toggle the RF output")
            }
            GridRow {
                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                VStack(spacing: 2) {
                    Image(systemName: aux == .syncOut ? "arrow.down" : "arrow.up")
                        .foregroundStyle(.secondary)
                    DiagramBox { Text(aux.label.uppercased()).bold() }
                }
                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Signal path. Reference \(aux == .externalReference ? "external" : "internal"), RF output \(rfLabel), AUX \(aux.label)")
    }

    private var rfLabel: String {
        switch rfOn {
        case true?: return "ON"
        case false?: return "OFF"
        case nil: return "--"
        }
    }

    private var rfColor: Color {
        switch rfOn {
        case true?: return .green
        case false?: return .red
        case nil: return .secondary
        }
    }
}
