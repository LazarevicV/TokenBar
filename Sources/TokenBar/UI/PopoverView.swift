import SwiftUI

struct PopoverView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("TokenBar — loading…")
                .font(.headline)
            HStack {
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
                    .keyboardShortcut("q")
            }
        }
        .padding()
        .frame(width: 280)
    }
}
