import SkillsHubCore
import SwiftUI

struct ContentView: View {
    var body: some View {
        Text("SkillsHub \(CatalogIndex.supportedSchemaVersion)")
            .padding()
    }
}

#Preview {
    ContentView()
}
