//
//  ChoreCatalogView.swift
//  houseWork
//
//  Main screen displaying chore templates, filters, and creation sheet.
//

import SwiftUI
import Combine

struct ChoreCatalogView: View {
    @EnvironmentObject private var taskStore: TaskBoardStore
    @EnvironmentObject private var authStore: AuthStore
    @EnvironmentObject private var householdStore: HouseholdStore
    @StateObject private var viewModel: ChoreCatalogViewModel
    @State private var showFormSheet = false
    @State private var draft = ChoreTemplateDraft()
    @State private var editingTemplate: ChoreTemplate?
    @State private var successMessage: String?
    @State private var showSuccessBanner = false
    @State private var alertMessage: String?
    @FocusState private var isSearchFieldFocused: Bool
    
    typealias ViewModelBuilder = @MainActor () -> ChoreCatalogViewModel
    
    @MainActor
    init(viewModelBuilder: @escaping ViewModelBuilder = { ChoreCatalogViewModel() }) {
        _viewModel = StateObject(wrappedValue: viewModelBuilder())
    }
    
    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                VStack(spacing: 12) {
                    searchField
                    tagFilter
                    templateList
                }
                .padding(.horizontal)
                .padding(.top, 16)
                .overlay(alignment: .top) {
                    if showSuccessBanner, let message = successMessage {
                        SuccessBanner(message: message)
                            .padding(.top, 8)
                    }
                }
                floatingAddButton
            }
        }
        .sheet(isPresented: $showFormSheet) {
            NavigationStack {
                ChoreTemplateForm(draft: $draft, isEditing: editingTemplate != nil) { template in
                    let isEditingExistingTemplate = editingTemplate != nil
                    Task {
                        if isEditingExistingTemplate {
                            await viewModel.updateTemplate(template)
                        } else {
                            await viewModel.createTemplate(template)
                        }
                    }
                    editingTemplate = nil
                    showFormSheet = false
                }
            }
        }
        .task {
            viewModel.startListening(for: householdStore.householdId)
        }
        .onChange(of: householdStore.householdId) { newId in
            viewModel.startListening(for: newId)
        }
        .onReceive(viewModel.$error.compactMap { $0 }) { message in
            alertMessage = message
        }
        .onReceive(viewModel.$mutationError.compactMap { $0 }) { message in
            alertMessage = message
        }
        .alert(
            "Catalog Error",
            isPresented: Binding(
                get: { alertMessage != nil },
                set: { if !$0 { alertMessage = nil } }
            ),
            actions: {
                Button("OK", role: .cancel) { }
            },
            message: {
                Text(alertMessage ?? "")
            }
        )
    }
    
    private func presentCreateForm() {
        dismissSearchFieldFocus()
        draft = ChoreTemplateDraft()
        editingTemplate = nil
        showFormSheet = true
    }
    
    private func presentEditForm(for template: ChoreTemplate) {
        dismissSearchFieldFocus()
        draft = ChoreTemplateDraft(template: template)
        editingTemplate = template
        showFormSheet = true
    }
    
    private func dismissSearchFieldFocus() {
        isSearchFieldFocused = false
    }

    private var floatingAddButton: some View {
        Button {
            presentCreateForm()
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 56, height: 56)
                .background(Color.accentColor, in: Circle())
                .shadow(color: Color.accentColor.opacity(0.3), radius: 8, x: 0, y: 4)
        }
        .padding(.trailing, 16)
        .padding(.bottom, 16)
        .accessibilityLabel("New Template")
    }
    
    private var searchField: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search chores or details", text: $viewModel.searchText)
                .focused($isSearchFieldFocused)
            if !viewModel.searchText.isEmpty {
                Button {
                    viewModel.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
    
    private var tagFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterChip(
                    label: "All",
                    isSelected: viewModel.selectedTag == nil
                ) {
                    dismissSearchFieldFocus()
                    viewModel.selectedTag = nil
                }
                
                ForEach(viewModel.availableTags, id: \.self) { tag in
                    FilterChip(label: tag, isSelected: viewModel.selectedTag == tag) {
                        dismissSearchFieldFocus()
                        viewModel.selectedTag = tag
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .simultaneousGesture(
            TapGesture().onEnded { dismissSearchFieldFocus() }
        )
    }
    
    private var templateList: some View {
        List {
            if viewModel.isLoading && viewModel.templates.isEmpty {
                HStack {
                    Spacer()
                    ProgressView("Loading catalog…")
                    Spacer()
                }
                .listRowInsets(EdgeInsets(top: 32, leading: 0, bottom: 32, trailing: 0))
            } else if viewModel.filteredTemplates.isEmpty {
                ContentUnavailableView(
                    "No chores found",
                    systemImage: "square.dashed.inset.filled",
                    description: Text("Try clearing the filters or creating a new template.")
                )
            } else {
                ForEach(viewModel.filteredTemplates) { template in
                    ChoreTemplateRow(
                        template: template,
                        onAddToBoard: { handleAddToBoard(template) },
                        onEdit: { presentEditForm(for: template) }
                    )
                    .listRowInsets(EdgeInsets(top: 12, leading: 0, bottom: 12, trailing: 0))
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            Task {
                                await viewModel.deleteTemplate(template)
                            }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .refreshable {
            await viewModel.refresh()
        }
        .simultaneousGesture(
            TapGesture().onEnded { dismissSearchFieldFocus() }
        )
    }
    
    private func handleAddToBoard(_ template: ChoreTemplate) {
        Task {
            let succeeded = await taskStore.enqueue(template: template, assignedTo: authStore.currentUser)
            guard succeeded else { return }
            await MainActor.run {
                if let user = authStore.currentUser {
                    successMessage = "\"\(template.title)\" assigned to \(user.name)"
                } else {
                    successMessage = "\"\(template.title)\" added to backlog"
                }
                withAnimation(.spring()) {
                    showSuccessBanner = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    withAnimation(.easeOut) {
                        showSuccessBanner = false
                    }
                }
            }
        }
    }
}

struct ChoreCatalogView_Previews: PreviewProvider {
    @MainActor
    static var previews: some View {
        let householdStore = HouseholdStore()
        let tagStore = TagStore(householdStore: householdStore)
        return ChoreCatalogView(viewModelBuilder: { ChoreCatalogViewModel(templates: ChoreTemplate.samples) })
            .environmentObject(TaskBoardStore(previewTasks: TaskItem.fixtures()))
            .environmentObject(AuthStore())
            .environmentObject(householdStore)
            .environmentObject(tagStore)
    }
}

private struct SuccessBanner: View {
    let message: String
    
    var body: some View {
        Text(message)
            .font(.subheadline.bold())
            .padding(.vertical, 10)
            .padding(.horizontal, 16)
            .background(.thinMaterial, in: Capsule())
            .shadow(radius: 4)
            .transition(.move(edge: .top).combined(with: .opacity))
    }
}
