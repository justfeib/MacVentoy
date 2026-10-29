import SwiftUI
import Combine

// Modello disco
struct DiskInfo: Identifiable, Hashable, Equatable {
    let id = UUID()
    let device: String   // e.g. "/dev/disk2"
    let description: String // volume name
    let size: String
}

@MainActor final class InstallerViewModel: ObservableObject {
    @Published var disks: [DiskInfo] = []
    @Published var selectedDisk: DiskInfo? = nil
    @Published var log: String = ""
    @Published var isRunning: Bool = false
    @Published var showConfirm: Bool = false

    // Carica i dischi rimovibili usando diskutil list -plist
    func loadDisks() {
        let task = Process()
        task.launchPath = "/usr/sbin/diskutil"
        task.arguments = ["list", "-plist"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        task.launch()
        task.waitUntilExit()
        guard task.terminationStatus == 0 else {
            appendLog("diskutil failed with status \(task.terminationStatus)\n")
            return
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
              let all = plist["AllDisksAndPartitions"] as? [[String: Any]] else {
            appendLog("Unable to parse diskutil plist output\n")
            return
        }
        var removable: [DiskInfo] = []
        for d in all {
            // Accept any removable device or any non‑internal (external) device
            guard let dev = d["DeviceIdentifier"] as? String else { continue }
            let removableFlag = d["RemovableMedia"] as? Bool ?? false
            let internalFlag = d["OSInternal"] as? Bool ?? true
            guard removableFlag || internalFlag == false else { continue }
            let sizeBytes = d["Size"] as? UInt64 ?? 0
            let sizeStr = ByteCountFormatter.string(fromByteCount: Int64(sizeBytes), countStyle: .file)
            let volName = d["VolumeName"] as? String ?? "Untitled"
            removable.append(DiskInfo(device: "/dev/\(dev)", description: volName, size: sizeStr))
        }
        DispatchQueue.main.async {
            self.disks = removable
            if self.selectedDisk == nil { self.selectedDisk = removable.first }
        }
    }

    func startInstallation() {
        guard selectedDisk != nil else { return }
        showConfirm = true
    }

    func runInstallation() {
        guard let disk = selectedDisk else { return }
        // Mark as running – UI will be disabled
        isRunning = true
        showConfirm = false

        // Locate the helper script inside the bundle resources (SwiftPM or main bundle)
        var scriptPath: String? = Bundle.module.path(forResource: "createVentoy", ofType: "sh")
        if scriptPath == nil {
            scriptPath = Bundle.main.path(forResource: "createVentoy", ofType: "sh", inDirectory: "Resources")
        }
        if scriptPath == nil, let res = Bundle.main.resourcePath {
            scriptPath = (res as NSString).appendingPathComponent("createVentoy.sh")
        }
        guard let script = scriptPath else {
            appendLog("Error: createVentoy.sh not found in bundle resources.\n")
            isRunning = false
            return
        }
        if !FileManager.default.fileExists(atPath: script) {
            appendLog("Error: Script file does not exist at \(script).\n")
            isRunning = false
            return
        }

        appendLog("Starting installation on \(disk.device)...\n")
        // Execute AppleScript on a background queue to avoid blocking the UI
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let appleScript = "do shell script \"\(script) \(disk.device)\" with administrator privileges"
            var error: NSDictionary?
            var output: String? = nil
            if let ascript = NSAppleScript(source: appleScript) {
                let result = ascript.executeAndReturnError(&error)
                output = result.stringValue
            }
            DispatchQueue.main.async {
                if let out = output {
                    self?.appendLog(out + "\n")
                } else if let err = error {
                    self?.appendLog("AppleScript error: \(err)\n")
                }
                // Reset running state
                self?.isRunning = false
            }
        }
    }

    private func appendLog(_ text: String) {
        DispatchQueue.main.async {
            self.log += text
        }
    }
}

struct ContentView: View {
    @StateObject private var vm = InstallerViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Ventoy – Create USB (macOS)")
                .font(.title2)

            Picker("Select Disk", selection: $vm.selectedDisk) {
                ForEach(vm.disks) { d in
                    Text("\(d.device) – \(d.description) – \(d.size)")
                        .tag(d as DiskInfo?)
                }
            }
            .pickerStyle(MenuPickerStyle())
            .disabled(vm.isRunning)

            HStack {
                Button("Refresh") { vm.loadDisks() }
                Spacer()
                Button("Create Ventoy USB") { vm.startInstallation() }
                    .disabled(vm.selectedDisk == nil || vm.isRunning)
            }

            Divider()

            ScrollView {
                Text(vm.log)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .border(Color.gray.opacity(0.3))
            .frame(minHeight: 200)
        }
        .padding()
        .onAppear { vm.loadDisks() }
        .alert(isPresented: $vm.showConfirm) {
            Alert(title: Text("Confirm"),
                  message: Text("All data on \(vm.selectedDisk?.device ?? "") will be erased. Continue?"),
                  primaryButton: .destructive(Text("Proceed")) { vm.runInstallation() },
                  secondaryButton: .cancel())
        }
    }
}
