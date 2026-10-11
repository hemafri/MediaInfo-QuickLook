import SwiftUI
import AppKit

struct MediaTable: NSViewRepresentable {
    @ObservedObject var model: AppModel
    static let titles = ["文件名", "HDR 分类", "Transfer", "色域", "位深", "色度采样", "编码", "分辨率", "帧率", "码率", "时长", "提示 / 错误"]
    func makeCoordinator() -> Coordinator { Coordinator(model) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = true
        let table = NSTableView(); table.usesAlternatingRowBackgroundColors = true; table.allowsMultipleSelection = true
        table.columnAutoresizingStyle = .noColumnAutoresizing; table.rowHeight = 25
        table.autosaveName = "MediaInfoColumns"; table.autosaveTableColumns = true
        for (index, title) in Self.titles.enumerated() {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("\(index)")); column.title = title
            column.width = index == 0 ? 260 : (index == 11 ? 280 : 115); column.minWidth = 60
            column.sortDescriptorPrototype = NSSortDescriptor(key: "\(index)", ascending: true)
            if index > 0 { column.isHidden = UserDefaults.standard.bool(forKey: "hideColumn\(index)") }
            table.addTableColumn(column)
        }
        table.delegate = context.coordinator; table.dataSource = context.coordinator
        table.target = context.coordinator; table.doubleAction = #selector(Coordinator.doubleClick(_:))
        table.sortDescriptors = [NSSortDescriptor(key: "\(model.sortColumn)", ascending: model.sortAscending)]
        let menu = NSMenu()
        for (index, title) in Self.titles.enumerated() where index > 0 {
            let item = NSMenuItem(title: title, action: #selector(Coordinator.toggleColumn(_:)), keyEquivalent: "")
            item.tag = index; item.target = context.coordinator; item.state = table.tableColumns[index].isHidden ? .off : .on; menu.addItem(item)
        }
        table.headerView?.menu = menu
        table.setAccessibilityLabel("视频元数据表格。双击打开预览。右键表头选择显示列。")
        scroll.documentView = table; context.coordinator.table = table
        return scroll
    }
    func updateNSView(_ view: NSScrollView, context: Context) {
        let c = context.coordinator; c.model = model; c.rows = model.visibleRows
        guard let table = c.table else { return }
        let origin = view.contentView.bounds.origin
        c.updating = true
        table.reloadData()
        table.selectRowIndexes(IndexSet(c.rows.indices.filter { model.selectedIDs.contains(c.rows[$0].id) }), byExtendingSelection: false)
        view.contentView.scroll(to: origin); view.reflectScrolledClipView(view.contentView)
        c.updating = false
    }
    @MainActor final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var model: AppModel; var rows: [MediaRow] = []; weak var table: NSTableView?; var updating = false
        init(_ model: AppModel) { self.model = model; rows = model.visibleRows }
        func numberOfRows(in tableView: NSTableView) -> Int { rows.count }
        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard rows.indices.contains(row), let index = Int(tableColumn?.identifier.rawValue ?? "0") else { return nil }
            let field = NSTextField(labelWithString: model.cells(rows[row])[index]); field.lineBreakMode = .byTruncatingMiddle
            field.toolTip = index == 0 ? rows[row].url.path : field.stringValue
            field.setAccessibilityLabel("\(MediaTable.titles[index])：\(field.stringValue)")
            return field
        }
        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !updating, let table else { return }
            model.selectedIDs = Set(table.selectedRowIndexes.compactMap { rows.indices.contains($0) ? rows[$0].id : nil })
        }
        func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
            guard let sort = tableView.sortDescriptors.first, let index = Int(sort.key ?? "0") else { return }
            model.sortColumn = index; model.sortAscending = sort.ascending
            UserDefaults.standard.set(index, forKey: "sortColumn"); UserDefaults.standard.set(sort.ascending, forKey: "sortAscending")
        }
        @objc func doubleClick(_ sender: NSTableView) { if rows.indices.contains(sender.clickedRow) { model.previewID = rows[sender.clickedRow].id } }
        @objc func toggleColumn(_ sender: NSMenuItem) {
            guard let column = table?.tableColumns.first(where: { $0.identifier.rawValue == "\(sender.tag)" }) else { return }
            column.isHidden.toggle(); sender.state = column.isHidden ? .off : .on
            UserDefaults.standard.set(column.isHidden, forKey: "hideColumn\(sender.tag)")
        }
    }
}
