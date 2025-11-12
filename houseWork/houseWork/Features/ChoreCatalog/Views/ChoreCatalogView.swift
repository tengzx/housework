//
//  ChoreCatalogView.swift
//  houseWork
//
//  Main screen displaying chore templates, filters, and creation sheet.
//

import SwiftUI

struct ChoreCatalogView: View {
    @StateObject private var viewModel = ChoreCatalogViewModel()
    @State private var showCreateSheet = false
    @State private var draft = ChoreTemplateDraft()
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                searchField
                tagFilter
                templateList
            }
            .padding(.horizontal)
            .padding(.top, 16)
            .navigationTitle("Chore Catalog")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        draft = ChoreTemplateDraft()
                        showCreateSheet = true
                    } label: {
                        Label("New Template", systemImage: "plus.circle.fill")
                    }
                }
            }
        }
        .sheet(isPresented: $showCreateSheet) {
            NavigationStack {
                ChoreTemplateForm(draft: $draft) { template in
                    viewModel.addTemplate(template)
                    showCreateSheet = false
                }
            }
        }
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
                    ChoreTemplateRow(template: template)
                        .listRowInsets(EdgeInsets(top: 12, leading: 0, bottom: 12, trailing: 0))
                }
            }
        }
        .listStyle(.plain)
    }
}

#Preview {
    ChoreCatalogView()
}
