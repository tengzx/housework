//
//  ChoreCatalogView.swift
//  houseWork
//
//  Main screen displaying chore templates, filters, and creation sheet.
//

import SwiftUI

struct ChoreCatalogView: View {
    @EnvironmentObject private var taskStore: TaskBoardStore
    @StateObject private var viewModel = ChoreCatalogViewModel()
    @State private var showFormSheet = false
    @State private var draft = ChoreTemplateDraft()
    @State private var editingTemplate: ChoreTemplate?
    @State private var successMessage: String?
    @State private var showSuccessBanner = false
    
    var body: some View {
        NavigationStack {
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
            .navigationTitle("Chore Catalog")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        presentCreateForm()
                    } label: {
                        Label("New Template", systemImage: "plus.circle.fill")
                    }
                }
            }
        }
        .sheet(isPresented: $showFormSheet) {
            NavigationStack {
                ChoreTemplateForm(draft: $draft, isEditing: editingTemplate != nil) { template in
                    if editingTemplate != nil {
                        viewModel.updateTemplate(template)
                    } else {
                        viewModel.addTemplate(template)
                    }
                    editingTemplate = nil
                    showFormSheet = false
                }
            }
        }
    }
    
    private func presentCreateForm() {
        draft = ChoreTemplateDraft()
        editingTemplate = nil
        showFormSheet = true
    }
    
    private func presentEditForm(for template: ChoreTemplate) {
        draft = ChoreTemplateDraft(template: template)
        editingTemplate = template
        showFormSheet = true
    }
    
    private var searchField: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search chores or details", text: $viewModel.searchText)
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
                ) { viewModel.selectedTag = nil }
                
                ForEach(viewModel.availableTags, id: \.self) { tag in
                    FilterChip(label: tag, isSelected: viewModel.selectedTag == tag) {
                        viewModel.selectedTag = tag
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }
    
    private var templateList: some View {
        List {
            if viewModel.filteredTemplates.isEmpty {
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
                }
            }
        }
        .listStyle(.plain)
    }
    
    private func handleAddToBoard(_ template: ChoreTemplate) {
        taskStore.enqueue(template: template)
        successMessage = "\"\(template.title)\" added to backlog"
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

#Preview {
    ChoreCatalogView()
        .environmentObject(TaskBoardStore())
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
