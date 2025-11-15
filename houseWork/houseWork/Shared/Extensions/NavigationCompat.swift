import SwiftUI

@ViewBuilder
func navigationContainer<Content: View>(@ViewBuilder content: () -> Content) -> some View {
    if #available(iOS 16.0, *) {
        NavigationStack { content() }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
    } else {
        NavigationView { content() }
            .navigationViewStyle(StackNavigationViewStyle())
            .navigationBarTitleDisplayMode(.inline)
    }
}

extension View {
    @ViewBuilder
    func hideNavigationBar() -> some View {
        if #available(iOS 16.0, *) {
            self.toolbar(.hidden, for: .navigationBar)
        } else {
            self.navigationBarHidden(true)
        }
    }
}

#if DEBUG
@ViewBuilder
func navigationPreviewContainer<Content: View>(@ViewBuilder content: () -> Content) -> some View {
    navigationContainer(content: content)
}
#endif
