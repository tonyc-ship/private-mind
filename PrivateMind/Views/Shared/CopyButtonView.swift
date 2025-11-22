import SwiftUI

struct CopyButtonView: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "doc.on.doc")
                .renderingMode(.template)
                .foregroundColor(.primary)
                .imageScale(.medium)
                .padding(.vertical, 0)
                .padding(.horizontal)
                .contentShape(Rectangle())
        }
    }
}

#Preview {
    CopyButtonView(action: {})
} 