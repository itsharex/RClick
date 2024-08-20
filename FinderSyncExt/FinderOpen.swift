//
//  FinderSync.swift
//  FinderSyncExt
//
//  Created by 李旭 on 2024/4/4.
//

import AppKit
import Cocoa
import Darwin
import FinderSync
import os.log

private let logger = Logger(subsystem: subsystem, category: "menu")

class FinderOpen: FIFinderSync {
    var myFolderURL = URL(fileURLWithPath: "/Users/")
    var isHostAppOpen = true
    let menuStore = MenuItemStore()
    let folderStore = FolderItemStore()
    let finderChannel = FinderCommChannel()
    let messager = Messager.shared
    
    var bookmarkItems: [BookmarkFolderItem] = []
    
    override init() {
        super.init()
        logger.info("---- finderOpen init")
        finderChannel.setup(folderStore, menuStore)

        messager.on(name: "quit") { _ in
            self.isHostAppOpen = false
        }
        messager.on(name: "running") { _ in
            self.isHostAppOpen = true
            logger.warning("startt running")
        }
    }
    
    // MARK: - Primary Finder Sync protocol methods

    override func beginObservingDirectory(at url: URL) {
        // The user is now seeing the container's contents.
        // If they see it in more than one view at a time, we're only told once.
        NSLog("beginObservingDirectoryAtURL: %@", url.path as NSString)
        let dirs = FIFinderSyncController.default().directoryURLs!
        
        for dir in dirs {
            logger.notice("Sync directory set to \(dir.path)")
        }
    }
    
    override func endObservingDirectory(at url: URL) {
        // The user is no longer seeing the container's contents.
        NSLog("endObservingDirectoryAtURL: %@", url.path as NSString)
    }
    
    override func requestBadgeIdentifier(for url: URL) {
        NSLog("requestBadgeIdentifierForURL: %@", url.path as NSString)
        
        // For demonstration purposes, this picks one of our two badges, or no badge at all, based on the filename.
//        let whichBadge = abs(url.path.hash) % 3
//        let badgeIdentifier = ["", "One", "Two"][whichBadge]
//        FIFinderSyncController.default().setBadgeIdentifier(badgeIdentifier, for: url)
    }
    
    // MARK: - Menu and toolbar item support
    
    override var toolbarItemName: String {
        return "RClick"
    }
    
    override var toolbarItemToolTip: String {
        return "RClick: Click the toolbar item for a menu."
    }
    
    override var toolbarItemImage: NSImage {
        return NSImage(systemSymbolName: "computermouse", accessibilityDescription: "RClick Menu")!
    }
    
    @MainActor func initMenuDirs() throws {
        do {
            let bks = try folderStore.getBookmarkItems()
            logger.warning("start init fifindersync ")
            if bks.isEmpty {
                logger.warning("start init fifindersync empty ")
            } else {
                logger.warning("start init fifindersync  else")
                for dir in bks {
                    logger.warning("Sync directory set to \(dir.path) ")
                }
            }
        } catch {
            logger.error("Failed to load URLs: \(error)")
        }
    }
    
    @MainActor override func menu(for menuKind: FIMenuKind) -> NSMenu {
        // Produce a menu for the extension.
        
        let applicationMenu = NSMenu(title: "RClick")
        guard isHostAppOpen else {
            return applicationMenu
        }
        switch menuKind {
        case .contextualMenuForContainer:
            for nsmenu in createAppItems() {
                applicationMenu.addItem(nsmenu)
            }
                
            if let fileMenuItem = createFileCreateMenuItem() {
                applicationMenu.addItem(fileMenuItem)
            }
           
        case .contextualMenuForItems:
            NSLog("contextualMenuForItems")
            
            for nsmenu in createAppItems() {
                applicationMenu.addItem(nsmenu)
            }
            
            for item in createActionMenuItems() {
                applicationMenu.addItem(item)
            }
            
        default:
            print("Some other character")
        }
       
        return applicationMenu
    }
    
    @objc func createAppItems() -> [NSMenuItem] {
        var appMenuItems: [NSMenuItem] = []
        for item in menuStore.appItems {
            let menuItem = NSMenuItem()
            menuItem.target = self
            menuItem.title = String(localized: "Open With \(item.name)")
            menuItem.action = #selector(itemAction(_:))
            menuItem.toolTip = "\(item.name)"
            menuItem.tag = 0
            menuItem.image = NSWorkspace.shared.icon(forFile: item.url.path)
            appMenuItems.append(menuItem)
        }
        return appMenuItems
    }

    @objc func createActionMenuItems() -> [NSMenuItem] {
        var actionMenuitems: [NSMenuItem] = []
        
        for item in menuStore.actionItems.filter(\.enabled) {
            let menuItem = NSMenuItem()
            menuItem.target = self
            menuItem.title = String(localized: String.LocalizationValue(item.key))
            menuItem.action = #selector(itemAction(_:))
            menuItem.toolTip = "\(item.name)"
            menuItem.tag = 1
            menuItem.image = NSImage(systemSymbolName: item.iconName, accessibilityDescription: item.iconName)!
            logger.info("item key\(item.key)")
            actionMenuitems.append(menuItem)
        }
        return actionMenuitems
    }
    
    @MainActor @objc func itemAction(_ menuItem: NSMenuItem) {
        switch menuItem.tag {
        case 0:
            appOpen(menuItem, isContainer: false)
        case 1:
            actioning(menuItem, isContainer: false)
        case 2:
            createFile(menuItem, isContainer: false)
        default:
            break
        }
    }

    // 创建文件菜单容器
    @objc func createFileCreateMenuItem() -> NSMenuItem? {
        let enabledFiletypeItems =  menuStore.filetypeItems.filter(\.enabled)
        if enabledFiletypeItems.isEmpty {
            return nil
        }
        let menuItem = NSMenuItem()
        menuItem.title = String(localized: "New File")
        menuItem.image = NSImage(systemSymbolName: "doc.badge.plus", accessibilityDescription: "doc.badge.plus")!
        let submenu = NSMenu(title: "file create menu")
        for item in enabledFiletypeItems {
            let menuItem = NSMenuItem()
            menuItem.target = self
            menuItem.title = item.name
            menuItem.action = #selector(itemAction(_:))
            menuItem.toolTip = "\(item.name)"
            menuItem.tag = 2
           
            if let img = NSImage(named: item.iconName) {
                menuItem.image = img
            } else {
                logger.info("")
            }
           
            submenu.addItem(menuItem)
        }
        menuItem.submenu = submenu
        return menuItem
    }
    
    @MainActor @objc func ContainerAction(_ menuItem: NSMenuItem) {
        switch menuItem.tag {
        case 0:
            appOpen(menuItem, isContainer: true)
    
        default:
            break
        }
    }
    
    @MainActor @objc func createFile(_ menuItem: NSMenuItem, isContainer: Bool) {
        let item = menuStore.getFileCreateItem(name: menuItem.title)
        let url = FIFinderSyncController.default().targetedURL()
        
        if let target = url?.path(), let ext = item?.ext {
            messager.sendMessage(name: Key.messageFromFinder, data: MessagePayload(action: "Create File", target: [target], ext: ext))
        }
    }
    
    @MainActor @objc func actioning(_ menuItem: NSMenuItem, isContainer: Bool) {
        guard let item = menuStore.getActionItem(name: menuItem.title) else {
            logger.info("not item ad ")
            return
        }
            
        guard let urls = FIFinderSyncController.default().selectedItemURLs(), !urls.isEmpty else {
            logger.info("not urls")
            return
        }
        
        let urlstr = urls.map { $0.path }
        logger.info("test \(String(localized: String.LocalizationValue(item.key)))")
        messager.sendMessage(name: Key.messageFromFinder, data: MessagePayload(action: item.key, target: urlstr))
    }
    
    @objc func appOpen(_ menuItem: NSMenuItem, isContainer: Bool) {
        var target: String
        if isContainer {
            guard let targetURL = FIFinderSyncController.default().targetedURL()
            else { return }
            target = targetURL.path
            
        } else {
            let urls = FIFinderSyncController.default().selectedItemURLs()
            guard let targetURL = urls?.first
            else { return }
            target = targetURL.path
        }
        
        let item = menuStore.getAppItem(name: menuItem.title)
        if let appUrl = item?.url {
            messager.sendMessage(name: Key.messageFromFinder, data: MessagePayload(action: "open", target: [target], app: appUrl.path))
        }
    }
}
