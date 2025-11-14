import SwiftUI

@ViewBuilder
func navigationContainer<Content: View>(@ViewBuilder content: () -> Content) -> some View {
    if #available(iOS 16.0, *) {
        NavigationStack { content() }
    } else {
        NavigationView { content() }
            .navigationViewStyle(StackNavigationViewStyle())
    }
}

#if DEBUG
@ViewBuilder
func navigationPreviewContainer<Content: View>(@ViewBuilder content: () -> Content) -> some View {
    navigationContainer(content: content)
}
#endif
