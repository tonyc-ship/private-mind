import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("showRecordingLiveActivity") private var showRecordingLiveActivity = true

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("General")) {
                    Toggle("Show Lock Screen Timer", isOn: $showRecordingLiveActivity)
                }
                
                Section(header: Text("About")) {
                    Text("Private Mind")
                        .font(.headline)
                    Text("Local note storage only")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    SettingsView()
} 