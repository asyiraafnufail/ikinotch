
import AppKit
import Darwin
import IkiNotchCore
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: NotchSettings
    @ObservedObject var calendar: CalendarMonitor

    @State private var memoryFootprintMB: Double = Self.currentMemoryFootprintMB()

    var body: some View {
        Form {
            Section("General") {
                Toggle("Show Virtual Notch", isOn: $settings.isNotchVisible)

                Toggle("Launch at Login", isOn: Binding(
                    get: { settings.launchAtLoginEnabled },
                    set: { settings.setLaunchAtLogin($0) }
                ))

                if let error = settings.launchAtLoginError {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.orange)
                }

                Toggle("Auto-hide in Fullscreen Spaces", isOn: $settings.hideInFullscreen)
            }

            Section("Interaction") {
                Picker("Trigger Mode", selection: $settings.triggerMode) {
                    ForEach(NotchTriggerMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }

                Picker("Animation Style (In / Out)", selection: $settings.animationStyle) {
                    ForEach(NotchAnimationStyle.allCases) { style in
                        Text(style.displayName).tag(style)
                    }
                }

                if settings.triggerMode != .clickOnly {
                    Picker("Hover Delay (In / Out)", selection: $settings.hoverDelay) {
                        Text("50 ms").tag(0.05)
                        Text("100 ms").tag(0.10)
                        Text("150 ms").tag(0.15)
                        Text("200 ms").tag(0.20)
                    }
                    .pickerStyle(.segmented)
                }
            }

            Section("Appearance & Size") {
                Picker("Shape Style", selection: $settings.shapeStyle) {
                    ForEach(NotchShapeStyle.allCases) { style in
                        Text(style.displayName).tag(style)
                    }
                }
                .pickerStyle(.segmented)

                Picker("Notch Size", selection: $settings.sizePreset) {
                    ForEach(NotchSizePreset.allCases) { preset in
                        Text(preset.displayName).tag(preset)
                    }
                }

                if settings.sizePreset == .custom {
                    HStack {
                        Text("Width")
                        Slider(value: $settings.customWidth, in: 120...300, step: 2)
                        Text("\(Int(settings.customWidth)) pt")
                            .monospacedDigit()
                            .foregroundColor(.secondary)
                            .frame(width: 48, alignment: .trailing)
                    }

                    HStack {
                        Text("Height")
                        Slider(value: $settings.customHeight, in: 22...44, step: 1)
                        Text("\(Int(settings.customHeight)) pt")
                            .monospacedDigit()
                            .foregroundColor(.secondary)
                            .frame(width: 48, alignment: .trailing)
                    }
                }

                HStack {
                    Text("Horizontal Offset")
                    Slider(value: $settings.horizontalOffset, in: -300...300, step: 2)
                    Text("\(Int(settings.horizontalOffset)) pt")
                        .monospacedDigit()
                        .foregroundColor(.secondary)
                        .frame(width: 52, alignment: .trailing)
                    Button("Center") {
                        settings.resetPosition()
                    }
                }

                Picker("Idle Content", selection: $settings.idleStyle) {
                    ForEach(NotchIdleStyle.allCases) { style in
                        Text(style.displayName).tag(style)
                    }
                }
                .pickerStyle(.segmented)

                if settings.idleStyle == .custom {
                    TextField("Custom Text", text: $settings.customIdleText, prompt: Text("e.g. Deep Work"))
                        .textFieldStyle(.roundedBorder)
                    Toggle("Show Battery alongside Custom Text", isOn: $settings.customIdleShowBattery)
                }

                Toggle("Caps Lock Indicator", isOn: $settings.showCapsLockIndicator)
            }

            Section("Widgets") {
                Toggle("Clock & Date", isOn: $settings.showClock)
                Toggle("Battery Status", isOn: $settings.showBattery)
                Toggle("Now Playing (Browser, Music, Spotify)", isOn: $settings.showNowPlaying)
                Toggle("Calendar (Up Next)", isOn: $settings.showCalendar)
                Toggle("File Drop Shelf (Tray)", isOn: $settings.showFileShelf)

                if settings.showCalendar && calendar.authState == .notDetermined {
                    Button("Grant Calendar Permission") {
                        calendar.requestAccess()
                    }
                }
            }

            Section("Zero-Idle Efficiency") {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Event-Driven Architecture")
                            .font(.subheadline.weight(.semibold))
                        Text("0 polling timers when collapsed • App Nap enabled • Native IOKit & DistributedNotifications")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(String(format: "%.1f MB", memoryFootprintMB))
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .monospacedDigit()
                        Button("Refresh") {
                            memoryFootprintMB = Self.currentMemoryFootprintMB()
                        }
                        .font(.caption)
                        .buttonStyle(.link)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 540)
        .onAppear {
            memoryFootprintMB = Self.currentMemoryFootprintMB()
        }
    }

    private static func currentMemoryFootprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size) / 4
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        return Double(info.phys_footprint) / (1024.0 * 1024.0)
    }
}
