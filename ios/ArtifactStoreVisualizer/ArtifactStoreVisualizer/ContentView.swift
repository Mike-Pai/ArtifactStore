import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = DemoRunViewModel()

    var body: some View {
        DemoRunView(viewModel: viewModel)
            .background(Color(red: 0.96, green: 0.97, blue: 0.98))
    }
}

#Preview {
    ContentView()
}
