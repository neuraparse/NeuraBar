import Foundation
import SwiftUI

enum SupportedLanguage: String, CaseIterable, Codable, Identifiable {
    case auto, en, tr
    var id: String { rawValue }

    var label: String {
        switch self {
        case .auto: return "System"
        case .en: return "English"
        case .tr: return "Türkçe"
        }
    }

    var flag: String {
        switch self {
        case .auto: return "globe"
        case .en: return "🇬🇧"
        case .tr: return "🇹🇷"
        }
    }
}

/// String keys — every user-facing string gets one.
enum Loc: String {
    // App / header
    case appName
    case appTagline
    case subtitle_todos, subtitle_focus, subtitle_shortcuts, subtitle_automate
    case subtitle_clipboard, subtitle_notes, subtitle_record, subtitle_system, subtitle_ai

    // Tabs
    case tab_todos, tab_focus, tab_shortcuts, tab_automate
    case tab_clipboard, tab_notes, tab_record, tab_system, tab_ai

    // Record tab
    case record_audioStart, record_screenStart, record_stop
    case record_clickToStart, record_empty
    case record_opt_mic, record_opt_cursor, record_opt_notify
    case record_input, record_savedToast
    case record_notif_audioSaved, record_notif_screenSaved

    // Common
    case save, cancel, close, add, remove, delete, edit, done
    case search, loading, thinking, stop
    case retry, tryAgain, refresh
    case copied, copy

    // Header buttons
    case commandPalette, settings, quit

    // Command palette
    case palette_searchPlaceholder, palette_noResults
    case palette_section_tab, palette_section_todo, palette_section_note
    case palette_section_shortcut, palette_section_clip, palette_section_action
    case palette_tabSuffix, palette_taskLabel, palette_pasteAction
    case palette_startFocus, palette_pauseFocus, palette_clearCompleted, palette_askAI

    // Todos
    case todo_newPlaceholder, todo_tagPlaceholder, todo_empty, todo_noMatch
    case todo_filter_active, todo_filter_all, todo_filter_done
    case todo_countActive, todo_clearCompleted
    case todo_allDone, todo_doneCountSuffix, todo_tip
    case todo_priority, todo_priority_low, todo_priority_normal, todo_priority_high
    case todo_dueToday, todo_dueTomorrow, todo_dueNextWeek, todo_dueClear
    case todo_markDone, todo_markActive
    case todo_group_overdue, todo_group_today, todo_group_tomorrow
    case todo_group_thisWeek, todo_group_later, todo_group_noDate, todo_group_completed

    // Pomodoro
    case focus_start, focus_resume, focus_pause, focus_reset
    case focus_state_focus, focus_state_shortBreak, focus_state_longBreak, focus_state_idle
    case focus_statToday, focus_statNext
    case focus_notif_focusDoneTitle, focus_notif_focusDoneBody
    case focus_notif_breakDoneTitle, focus_notif_breakDoneBody
    case focus_sessionsSuffix
    case focus_mode_classic, focus_mode_extended, focus_mode_short, focus_mode_deep, focus_mode_custom
    case focus_skip, focus_extend5, focus_endsAt
    case focus_stat_streak, focus_stat_sessionsToday, focus_stat_focusTime
    case focus_autoBreak, focus_autoFocus
    case focus_dailyGoal
    case focus_custom_title, focus_custom_focus, focus_custom_shortBreak, focus_custom_longBreak

    // Shortcuts
    case shortcut_quickAccess, shortcut_addTitle
    case shortcut_type, shortcut_kind_app, shortcut_kind_folder, shortcut_kind_url, shortcut_kind_command
    case shortcut_name, shortcut_pathOrUrl, shortcut_symbol, shortcut_pick, shortcut_remove
    case shortcut_empty, shortcut_pin, shortcut_unpin, shortcut_launches
    case shortcut_edit, shortcut_copyPath, shortcut_importApps
    case shortcut_dropHere, shortcut_dropHint

    // Clipboard
    case clip_empty, clip_searchPlaceholder, clip_captured

    // Notes
    case notes_title, notes_titlePlaceholder, notes_untitled, notes_new, notes_empty
    case notes_welcomeTitle, notes_welcomeBody
    case notes_pin, notes_unpin, notes_duplicate, notes_copyBody, notes_color
    case notes_preview, notes_edit
    case notes_words, notes_chars, notes_minRead, notes_saved
    case notes_noMatch, notes_newFromClipboard
    case notes_group_pinned, notes_group_today, notes_group_yesterday, notes_group_thisWeek, notes_group_older

    // System
    case sys_cpu, sys_memory, sys_disk, sys_battery, sys_charging, sys_free, sys_used
    case sys_status_ok, sys_status_warning, sys_status_critical
    case sys_configure, sys_thresholds, sys_notify, sys_alert_title

    // Automation
    case auto_category_files, auto_category_cleanup, auto_category_system
    case auto_screenshots_title, auto_screenshots_sub
    case auto_dmg_title, auto_dmg_sub
    case auto_sortDL_title, auto_sortDL_sub
    case auto_dsstore_title, auto_dsstore_sub
    case auto_heic_title, auto_heic_sub
    case auto_bigFiles_title, auto_bigFiles_sub
    case auto_trash_title, auto_trash_sub
    case auto_derived_title, auto_derived_sub
    case auto_oldDownloads_title, auto_oldDownloads_sub
    case auto_hiddenFiles_title, auto_hiddenFiles_sub
    case auto_lockScreen_title, auto_lockScreen_sub
    case auto_sleep_title, auto_sleep_sub

    // Automation results
    case auto_run, auto_running, auto_showDetails, auto_hideDetails
    case auto_noRuns, auto_history, auto_clearHistory
    case auto_success, auto_failed, auto_stat_moved, auto_stat_deleted
    case auto_stat_skipped, auto_stat_converted, auto_stat_total, auto_stat_size, auto_stat_duration

    // AI assistant
    case ai_providers_count, ai_providers_emptyTitle, ai_providers_emptyBody
    case ai_picker_title, ai_picker_hint, ai_cli, ai_api, ai_desktop
    case ai_emptyPrompt, ai_emptyDesktopHint, ai_emptyCLIHint
    case ai_placeholder_cli, ai_placeholder_api, ai_placeholder_desktop
    case ai_desktopOpened, ai_rescan, ai_refreshList
    case ai_conversations, ai_newConversation, ai_noConversations, ai_untitled
    case ai_pin, ai_unpin, ai_rename, ai_duplicate

    // Settings
    case set_title, set_ai, set_general, set_about
    case set_aiDescription
    case set_apiKey, set_model, set_active, set_getApiKey
    case set_anthropic, set_openai, set_ollama, set_ollamaHint
    case set_launch_title, set_launch_body
    case set_dataFolder, set_revealFolder, set_shortcuts
    case set_language, set_language_body
    case set_autoSaveNote
    case set_sc_palette, set_sc_settings, set_sc_tabs, set_sc_quit, set_sc_global

    // About
    case about_version, about_description, about_copyright
}

private enum Dict {
    // English is the base. Translations fall back to English if a key is missing.
    static let en: [Loc: String] = [
        .appName: "NeuraBar",
        .appTagline: "Your menu-bar workspace",

        .subtitle_todos: "Your tasks, one place",
        .subtitle_focus: "Pomodoro · focus",
        .subtitle_shortcuts: "Quick access",
        .subtitle_automate: "One-click automation",
        .subtitle_clipboard: "Clipboard history",
        .subtitle_notes: "Your notes",
        .subtitle_record: "Audio & screen capture",
        .subtitle_system: "System monitor",
        .subtitle_ai: "AI assistant",

        .tab_todos: "Tasks",
        .tab_focus: "Focus",
        .tab_shortcuts: "Shortcuts",
        .tab_automate: "Automate",
        .tab_clipboard: "Clipboard",
        .tab_notes: "Notes",
        .tab_record: "Record",
        .tab_system: "System",
        .tab_ai: "AI",

        .record_audioStart: "Start audio",
        .record_screenStart: "Start screen",
        .record_stop: "Stop",
        .record_clickToStart: "Click to start",
        .record_empty: "No recordings yet",
        .record_opt_mic: "Include microphone",
        .record_opt_cursor: "Capture cursor",
        .record_opt_notify: "Notify when saved",
        .record_input: "Input",
        .record_savedToast: "Recording saved",
        .record_notif_audioSaved: "Audio recording saved",
        .record_notif_screenSaved: "Screen recording saved",

        .save: "Save", .cancel: "Cancel", .close: "Close", .add: "Add",
        .remove: "Remove", .delete: "Delete", .edit: "Edit", .done: "Done",
        .search: "Search", .loading: "Loading", .thinking: "thinking...", .stop: "Stop",
        .retry: "Retry", .tryAgain: "Try again", .refresh: "Refresh",
        .copied: "Copied", .copy: "Copy",

        .commandPalette: "Command palette (⌘K)",
        .settings: "Settings (⌘,)",
        .quit: "Quit (⌘Q)",

        .palette_searchPlaceholder: "Search or type a command…",
        .palette_noResults: "No results",
        .palette_section_tab: "Tab",
        .palette_section_todo: "Task",
        .palette_section_note: "Note",
        .palette_section_shortcut: "Shortcut",
        .palette_section_clip: "Clipboard",
        .palette_section_action: "Action",
        .palette_tabSuffix: "tab",
        .palette_taskLabel: "Task",
        .palette_pasteAction: "Paste",
        .palette_startFocus: "Start focus",
        .palette_pauseFocus: "Pause focus",
        .palette_clearCompleted: "Clear completed",
        .palette_askAI: "Ask AI",

        .todo_newPlaceholder: "New task… (prefix with ! for high priority)",
        .todo_tagPlaceholder: "tag",
        .todo_empty: "No tasks yet",
        .todo_noMatch: "No matches",
        .todo_filter_active: "Active",
        .todo_filter_all: "All",
        .todo_filter_done: "Done",
        .todo_countActive: "active",
        .todo_clearCompleted: "Clear done",
        .todo_allDone: "All done",
        .todo_doneCountSuffix: "done",
        .todo_tip: "⌘⇧N new  ·  !prefix for priority  ·  #tag to organize",
        .todo_priority: "Priority",
        .todo_priority_low: "Low",
        .todo_priority_normal: "Normal",
        .todo_priority_high: "High",
        .todo_dueToday: "Due today",
        .todo_dueTomorrow: "Due tomorrow",
        .todo_dueNextWeek: "Due next week",
        .todo_dueClear: "Clear due date",
        .todo_markDone: "Mark done",
        .todo_markActive: "Mark active",
        .todo_group_overdue: "Overdue",
        .todo_group_today: "Today",
        .todo_group_tomorrow: "Tomorrow",
        .todo_group_thisWeek: "This week",
        .todo_group_later: "Later",
        .todo_group_noDate: "Someday",
        .todo_group_completed: "Completed",

        .focus_start: "Start", .focus_resume: "Resume",
        .focus_pause: "Pause", .focus_reset: "Reset",
        .focus_state_focus: "Focus",
        .focus_state_shortBreak: "Short break",
        .focus_state_longBreak: "Long break",
        .focus_state_idle: "Idle",
        .focus_statToday: "Today",
        .focus_statNext: "Next break",
        .focus_notif_focusDoneTitle: "Focus complete 🎉",
        .focus_notif_focusDoneBody: "Take a short break.",
        .focus_notif_breakDoneTitle: "Break over",
        .focus_notif_breakDoneBody: "Back to focus.",
        .focus_sessionsSuffix: "focus left",
        .focus_mode_classic: "Classic",
        .focus_mode_extended: "Extended",
        .focus_mode_short: "Short",
        .focus_mode_deep: "Deep",
        .focus_mode_custom: "Custom",
        .focus_skip: "Skip",
        .focus_extend5: "+5 min",
        .focus_endsAt: "ends at",
        .focus_stat_streak: "Day streak",
        .focus_stat_sessionsToday: "Today",
        .focus_stat_focusTime: "Focus time",
        .focus_autoBreak: "Auto-start breaks",
        .focus_autoFocus: "Auto-start next focus",
        .focus_dailyGoal: "Daily goal (sessions)",
        .focus_custom_title: "Custom durations",
        .focus_custom_focus: "Focus",
        .focus_custom_shortBreak: "Short break",
        .focus_custom_longBreak: "Long break",

        .shortcut_quickAccess: "Quick access",
        .shortcut_addTitle: "Add shortcut",
        .shortcut_type: "Type",
        .shortcut_kind_app: "App",
        .shortcut_kind_folder: "Folder",
        .shortcut_kind_url: "URL",
        .shortcut_kind_command: "Command",
        .shortcut_name: "Name",
        .shortcut_pathOrUrl: "Path / URL / command",
        .shortcut_symbol: "SF Symbol (e.g. star, folder)",
        .shortcut_pick: "Choose…",
        .shortcut_remove: "Remove",
        .shortcut_empty: "No shortcuts yet",
        .shortcut_pin: "Pin to top",
        .shortcut_unpin: "Unpin",
        .shortcut_launches: "Launches",
        .shortcut_edit: "Edit",
        .shortcut_copyPath: "Copy path",
        .shortcut_importApps: "Import apps…",
        .shortcut_dropHere: "Drop to add",
        .shortcut_dropHint: "Drop .app files or folders from Finder",

        .clip_empty: "Clipboard history is empty\n(copy something → it appears)",
        .clip_searchPlaceholder: "Search…",
        .clip_captured: "Saved to history",

        .notes_title: "Notes",
        .notes_titlePlaceholder: "Title",
        .notes_untitled: "(untitled)",
        .notes_new: "New note",
        .notes_empty: "No notes",
        .notes_welcomeTitle: "Welcome",
        .notes_welcomeBody: "Type freely. Markdown works — try **bold**, _italic_, `code`, or a #tag.\n\n⌘⇧N new · ⌘D duplicate · ⌘/ preview · ⌘; timestamp",
        .notes_pin: "Pin",
        .notes_unpin: "Unpin",
        .notes_duplicate: "Duplicate",
        .notes_copyBody: "Copy body",
        .notes_color: "Color",
        .notes_preview: "Preview",
        .notes_edit: "Edit",
        .notes_words: "words",
        .notes_chars: "chars",
        .notes_minRead: "min read",
        .notes_saved: "Saved",
        .notes_noMatch: "No matches",
        .notes_newFromClipboard: "New from clipboard",
        .notes_group_pinned: "Pinned",
        .notes_group_today: "Today",
        .notes_group_yesterday: "Yesterday",
        .notes_group_thisWeek: "This week",
        .notes_group_older: "Older",

        .sys_cpu: "CPU", .sys_memory: "Memory", .sys_disk: "Disk",
        .sys_battery: "Battery", .sys_charging: "charging", .sys_free: "free", .sys_used: "used",
        .sys_status_ok: "All systems nominal",
        .sys_status_warning: "Needs attention",
        .sys_status_critical: "Critical",
        .sys_configure: "Configure thresholds",
        .sys_thresholds: "Alert thresholds",
        .sys_notify: "Send notification on critical",
        .sys_alert_title: "System under pressure",

        .auto_category_files: "Files",
        .auto_category_cleanup: "Cleanup",
        .auto_category_system: "System",

        .auto_screenshots_title: "Sort screenshots",
        .auto_screenshots_sub: "Group Desktop screenshots by month",
        .auto_dmg_title: "Clear installers",
        .auto_dmg_sub: "Move .dmg/.pkg/.msi from Downloads",
        .auto_sortDL_title: "Sort Downloads by type",
        .auto_sortDL_sub: "PDFs, Images, Videos, Documents, Archives",
        .auto_dsstore_title: "Purge .DS_Store",
        .auto_dsstore_sub: "Recursively delete .DS_Store files in home",
        .auto_heic_title: "HEIC → JPG",
        .auto_heic_sub: "Convert .heic files on Desktop via sips",
        .auto_bigFiles_title: "Largest files",
        .auto_bigFiles_sub: "Top 20 in Downloads + Desktop",
        .auto_trash_title: "Empty Trash",
        .auto_trash_sub: "Free up space from Trash",
        .auto_derived_title: "Clean DerivedData",
        .auto_derived_sub: "Remove Xcode build caches",
        .auto_oldDownloads_title: "Archive old downloads",
        .auto_oldDownloads_sub: "Move items older than 30 days to _archive",
        .auto_hiddenFiles_title: "Toggle hidden files",
        .auto_hiddenFiles_sub: "Show or hide dotfiles in Finder",
        .auto_lockScreen_title: "Lock screen",
        .auto_lockScreen_sub: "Require password immediately",
        .auto_sleep_title: "Sleep display",
        .auto_sleep_sub: "Turn the display off now",

        .auto_run: "Run",
        .auto_running: "Running…",
        .auto_showDetails: "Show details",
        .auto_hideDetails: "Hide details",
        .auto_noRuns: "No runs yet — pick an automation below.",
        .auto_history: "Recent runs",
        .auto_clearHistory: "Clear history",
        .auto_success: "Success",
        .auto_failed: "Failed",
        .auto_stat_moved: "Moved",
        .auto_stat_deleted: "Deleted",
        .auto_stat_skipped: "Skipped",
        .auto_stat_converted: "Converted",
        .auto_stat_total: "Total",
        .auto_stat_size: "Size",
        .auto_stat_duration: "Duration",

        .ai_providers_count: "providers",
        .ai_providers_emptyTitle: "No AI provider found",
        .ai_providers_emptyBody: "Add an API key or install Claude / Codex / Ollama CLI or a desktop app.",
        .ai_picker_title: "Pick provider",
        .ai_picker_hint: "%d CLI · %d API · %d desktop",
        .ai_cli: "CLI",
        .ai_api: "API",
        .ai_desktop: "Desktop",
        .ai_emptyPrompt: "Ask anything!",
        .ai_emptyDesktopHint: "Message will be copied and %@ will open.",
        .ai_emptyCLIHint: "Using %@.",
        .ai_placeholder_cli: "Message %@…",
        .ai_placeholder_api: "Ask %@…",
        .ai_placeholder_desktop: "Message to send to the app…",
        .ai_desktopOpened: "%@ opened. Prompt copied — press ⌘V to paste.",
        .ai_rescan: "Re-scan providers",
        .ai_refreshList: "Refresh",
        .ai_conversations: "Conversations",
        .ai_newConversation: "New chat",
        .ai_noConversations: "No chats yet",
        .ai_untitled: "Untitled",
        .ai_pin: "Pin",
        .ai_unpin: "Unpin",
        .ai_rename: "Rename",
        .ai_duplicate: "Duplicate",

        .set_title: "Settings",
        .set_ai: "AI",
        .set_general: "General",
        .set_about: "About",
        .set_aiDescription: "Changes aren't saved automatically — press Save.",
        .set_apiKey: "API Key",
        .set_model: "Model",
        .set_active: "Active",
        .set_getApiKey: "Get API key",
        .set_anthropic: "Anthropic Claude",
        .set_openai: "OpenAI",
        .set_ollama: "Ollama (Local)",
        .set_ollamaHint: "If Ollama CLI is installed it's used automatically. Just enter a model name.",
        .set_launch_title: "Launch at login",
        .set_launch_body: "NeuraBar opens quietly when macOS starts.",
        .set_dataFolder: "Data folder",
        .set_revealFolder: "Reveal in Finder",
        .set_shortcuts: "Keyboard shortcuts",
        .set_language: "Language",
        .set_language_body: "Interface language. \"System\" follows macOS.",
        .set_autoSaveNote: "This tab auto-saves.",
        .set_sc_palette: "Command palette",
        .set_sc_settings: "Settings",
        .set_sc_tabs: "Switch tabs",
        .set_sc_quit: "Quit",
        .set_sc_global: "Open NeuraBar (global)",

        .about_version: "%@ · macOS 26 Tahoe",
        .about_description: "A menu-bar workspace for your day.",
        .about_copyright: "© 2026 Bayram Eker"
    ]

    static let tr: [Loc: String] = [
        .appName: "NeuraBar",
        .appTagline: "Menü çubuğu iş alanın",

        .subtitle_todos: "Görevlerin, tek yer",
        .subtitle_focus: "Pomodoro · fokus",
        .subtitle_shortcuts: "Hızlı erişim",
        .subtitle_automate: "Tek tıkla otomasyon",
        .subtitle_clipboard: "Pano geçmişi",
        .subtitle_notes: "Notların",
        .subtitle_record: "Ses & ekran kaydı",
        .subtitle_system: "Sistem izleme",
        .subtitle_ai: "Yapay zeka asistanı",

        .tab_todos: "Görevler",
        .tab_focus: "Fokus",
        .tab_shortcuts: "Kısayollar",
        .tab_automate: "Otomasyon",
        .tab_clipboard: "Pano",
        .tab_notes: "Notlar",
        .tab_record: "Kayıt",
        .tab_system: "Sistem",
        .tab_ai: "AI",

        .record_audioStart: "Ses kaydı başlat",
        .record_screenStart: "Ekran kaydı başlat",
        .record_stop: "Durdur",
        .record_clickToStart: "Başlatmak için tıkla",
        .record_empty: "Henüz kayıt yok",
        .record_opt_mic: "Mikrofonu dahil et",
        .record_opt_cursor: "İmleci yakala",
        .record_opt_notify: "Kaydedilince bildirim",
        .record_input: "Giriş",
        .record_savedToast: "Kayıt kaydedildi",
        .record_notif_audioSaved: "Ses kaydı kaydedildi",
        .record_notif_screenSaved: "Ekran kaydı kaydedildi",

        .save: "Kaydet", .cancel: "İptal", .close: "Kapat", .add: "Ekle",
        .remove: "Kaldır", .delete: "Sil", .edit: "Düzenle", .done: "Tamam",
        .search: "Ara", .loading: "Yükleniyor", .thinking: "düşünüyor...", .stop: "Durdur",
        .retry: "Tekrar", .tryAgain: "Yeniden dene", .refresh: "Yenile",
        .copied: "Kopyalandı", .copy: "Kopyala",

        .commandPalette: "Komut paleti (⌘K)",
        .settings: "Ayarlar (⌘,)",
        .quit: "Çıkış (⌘Q)",

        .palette_searchPlaceholder: "Ara veya komut yaz…",
        .palette_noResults: "Sonuç yok",
        .palette_section_tab: "Sekme",
        .palette_section_todo: "Görev",
        .palette_section_note: "Not",
        .palette_section_shortcut: "Kısayol",
        .palette_section_clip: "Pano",
        .palette_section_action: "Aksiyon",
        .palette_tabSuffix: "sekmesi",
        .palette_taskLabel: "Görev",
        .palette_pasteAction: "Yapıştır",
        .palette_startFocus: "Fokus başlat",
        .palette_pauseFocus: "Fokus duraklat",
        .palette_clearCompleted: "Biteni sil",
        .palette_askAI: "AI'ya sor",

        .todo_newPlaceholder: "Yeni görev… (önemlisi için ! ile başlat)",
        .todo_tagPlaceholder: "etiket",
        .todo_empty: "Hiç görev yok",
        .todo_noMatch: "Eşleşme yok",
        .todo_filter_active: "Aktif",
        .todo_filter_all: "Hepsi",
        .todo_filter_done: "Bitti",
        .todo_countActive: "aktif",
        .todo_clearCompleted: "Biteni sil",
        .todo_allDone: "Hepsi bitti",
        .todo_doneCountSuffix: "tamam",
        .todo_tip: "⌘⇧N yeni  ·  ! önek öncelik  ·  #etiket düzen",
        .todo_priority: "Öncelik",
        .todo_priority_low: "Düşük",
        .todo_priority_normal: "Normal",
        .todo_priority_high: "Yüksek",
        .todo_dueToday: "Bugün",
        .todo_dueTomorrow: "Yarın",
        .todo_dueNextWeek: "Gelecek hafta",
        .todo_dueClear: "Tarihi temizle",
        .todo_markDone: "Tamamlandı",
        .todo_markActive: "Aktif yap",
        .todo_group_overdue: "Gecikmiş",
        .todo_group_today: "Bugün",
        .todo_group_tomorrow: "Yarın",
        .todo_group_thisWeek: "Bu hafta",
        .todo_group_later: "Sonra",
        .todo_group_noDate: "Bir gün",
        .todo_group_completed: "Tamamlanan",

        .focus_start: "Başla", .focus_resume: "Devam",
        .focus_pause: "Duraklat", .focus_reset: "Sıfırla",
        .focus_state_focus: "Fokus",
        .focus_state_shortBreak: "Kısa mola",
        .focus_state_longBreak: "Uzun mola",
        .focus_state_idle: "Bekliyor",
        .focus_statToday: "Bugün",
        .focus_statNext: "Sıradaki mola",
        .focus_notif_focusDoneTitle: "Fokus bitti 🎉",
        .focus_notif_focusDoneBody: "Biraz mola ver.",
        .focus_notif_breakDoneTitle: "Mola bitti",
        .focus_notif_breakDoneBody: "Tekrar fokus zamanı.",
        .focus_sessionsSuffix: "fokus",
        .focus_mode_classic: "Klasik",
        .focus_mode_extended: "Uzun",
        .focus_mode_short: "Kısa",
        .focus_mode_deep: "Derin",
        .focus_mode_custom: "Özel",
        .focus_skip: "Atla",
        .focus_extend5: "+5 dk",
        .focus_endsAt: "bitiş",
        .focus_stat_streak: "Gün serisi",
        .focus_stat_sessionsToday: "Bugün",
        .focus_stat_focusTime: "Fokus süresi",
        .focus_autoBreak: "Molayı otomatik başlat",
        .focus_autoFocus: "Sonraki fokusu otomatik başlat",
        .focus_dailyGoal: "Günlük hedef (seans)",
        .focus_custom_title: "Özel süreler",
        .focus_custom_focus: "Fokus",
        .focus_custom_shortBreak: "Kısa mola",
        .focus_custom_longBreak: "Uzun mola",

        .shortcut_quickAccess: "Hızlı erişim",
        .shortcut_addTitle: "Kısayol Ekle",
        .shortcut_type: "Tip",
        .shortcut_kind_app: "Uygulama",
        .shortcut_kind_folder: "Klasör",
        .shortcut_kind_url: "URL",
        .shortcut_kind_command: "Komut",
        .shortcut_name: "İsim",
        .shortcut_pathOrUrl: "Yol / URL / komut",
        .shortcut_symbol: "SF Symbol (ör: star, folder)",
        .shortcut_pick: "Seç…",
        .shortcut_remove: "Kaldır",
        .shortcut_empty: "Hiç kısayol yok",
        .shortcut_pin: "Üste sabitle",
        .shortcut_unpin: "Sabitlemeyi kaldır",
        .shortcut_launches: "Açılış sayısı",
        .shortcut_edit: "Düzenle",
        .shortcut_copyPath: "Yolu kopyala",
        .shortcut_importApps: "Uygulamaları içe aktar…",
        .shortcut_dropHere: "Eklemek için bırak",
        .shortcut_dropHint: "Finder'dan .app veya klasör sürükle",

        .clip_empty: "Pano geçmişi boş\n(kopyala → görünsün)",
        .clip_searchPlaceholder: "Ara…",
        .clip_captured: "Geçmişe kaydedildi",

        .notes_title: "Notlar",
        .notes_titlePlaceholder: "Başlık",
        .notes_untitled: "(isimsiz)",
        .notes_new: "Yeni not",
        .notes_empty: "Hiç not yok",
        .notes_welcomeTitle: "Hoşgeldin",
        .notes_welcomeBody: "Serbestçe yaz. Markdown çalışır — **kalın**, _italik_, `kod` veya #etiket deneyebilirsin.\n\n⌘⇧N yeni · ⌘D çoğalt · ⌘/ önizleme · ⌘; zaman damgası",
        .notes_pin: "Sabitle",
        .notes_unpin: "Sabitlemeyi kaldır",
        .notes_duplicate: "Çoğalt",
        .notes_copyBody: "İçeriği kopyala",
        .notes_color: "Renk",
        .notes_preview: "Önizle",
        .notes_edit: "Düzenle",
        .notes_words: "kelime",
        .notes_chars: "karakter",
        .notes_minRead: "dk okuma",
        .notes_saved: "Kaydedildi",
        .notes_noMatch: "Eşleşme yok",
        .notes_newFromClipboard: "Panodan yeni not",
        .notes_group_pinned: "Sabitli",
        .notes_group_today: "Bugün",
        .notes_group_yesterday: "Dün",
        .notes_group_thisWeek: "Bu hafta",
        .notes_group_older: "Daha eski",

        .sys_cpu: "CPU", .sys_memory: "Bellek", .sys_disk: "Disk",
        .sys_battery: "Pil", .sys_charging: "şarj", .sys_free: "boş", .sys_used: "kullanılan",
        .sys_status_ok: "Her şey yolunda",
        .sys_status_warning: "Dikkat",
        .sys_status_critical: "Kritik",
        .sys_configure: "Eşikleri yapılandır",
        .sys_thresholds: "Uyarı eşikleri",
        .sys_notify: "Kritik olunca bildirim gönder",
        .sys_alert_title: "Sistem baskı altında",

        .auto_category_files: "Dosyalar",
        .auto_category_cleanup: "Temizlik",
        .auto_category_system: "Sistem",

        .auto_screenshots_title: "Ekran görüntülerini sırala",
        .auto_screenshots_sub: "Masaüstündeki Screenshot'ları ay ay ayır",
        .auto_dmg_title: "Installer temizle",
        .auto_dmg_sub: "Downloads'daki .dmg/.pkg/.msi taşı",
        .auto_sortDL_title: "Downloads'ı tipe göre ayır",
        .auto_sortDL_sub: "PDF, Resim, Video, Döküman, Arşiv",
        .auto_dsstore_title: ".DS_Store temizle",
        .auto_dsstore_sub: "Ev dizininde rekürsif .DS_Store sil",
        .auto_heic_title: "HEIC → JPG",
        .auto_heic_sub: "Masaüstündeki .heic → .jpg çevir",
        .auto_bigFiles_title: "En büyük dosyalar",
        .auto_bigFiles_sub: "Downloads + Desktop'ta ilk 20",
        .auto_trash_title: "Çöpü boşalt",
        .auto_trash_sub: "Çöp kutusunu boşaltarak yer aç",
        .auto_derived_title: "DerivedData temizle",
        .auto_derived_sub: "Xcode build önbelleklerini sil",
        .auto_oldDownloads_title: "Eski indirmeleri arşivle",
        .auto_oldDownloads_sub: "30 günden eski dosyaları _arsiv'e taşı",
        .auto_hiddenFiles_title: "Gizli dosya görünürlüğü",
        .auto_hiddenFiles_sub: "Finder'da dotfile'ları göster/gizle",
        .auto_lockScreen_title: "Ekranı kilitle",
        .auto_lockScreen_sub: "Hemen parola iste",
        .auto_sleep_title: "Ekranı uyut",
        .auto_sleep_sub: "Ekranı şimdi kapat",

        .auto_run: "Çalıştır",
        .auto_running: "Çalışıyor…",
        .auto_showDetails: "Detayları göster",
        .auto_hideDetails: "Detayları gizle",
        .auto_noRuns: "Henüz hiç çalışma yok — aşağıdan bir otomasyon seç.",
        .auto_history: "Son çalışmalar",
        .auto_clearHistory: "Geçmişi temizle",
        .auto_success: "Başarılı",
        .auto_failed: "Başarısız",
        .auto_stat_moved: "Taşınan",
        .auto_stat_deleted: "Silinen",
        .auto_stat_skipped: "Atlanan",
        .auto_stat_converted: "Çevrilen",
        .auto_stat_total: "Toplam",
        .auto_stat_size: "Boyut",
        .auto_stat_duration: "Süre",

        .ai_providers_count: "sağlayıcı",
        .ai_providers_emptyTitle: "Hiçbir AI sağlayıcısı bulunamadı",
        .ai_providers_emptyBody: "Bir API anahtarı ekle ya da Claude/Codex/Ollama CLI veya masaüstü uygulaması kur.",
        .ai_picker_title: "Sağlayıcı seç",
        .ai_picker_hint: "%d CLI · %d API · %d masaüstü",
        .ai_cli: "CLI",
        .ai_api: "API",
        .ai_desktop: "Masaüstü",
        .ai_emptyPrompt: "Bir şey sor!",
        .ai_emptyDesktopHint: "Mesaj kopyalanacak ve %@ açılacak.",
        .ai_emptyCLIHint: "%@ kullanılacak.",
        .ai_placeholder_cli: "%@'a komut yaz…",
        .ai_placeholder_api: "%@'a sor…",
        .ai_placeholder_desktop: "Uygulamaya gönderilecek mesaj…",
        .ai_desktopOpened: "%@ açıldı. Mesaj panoya kopyalandı — ⌘V ile yapıştır.",
        .ai_rescan: "Sağlayıcıları tekrar tara",
        .ai_refreshList: "Yenile",
        .ai_conversations: "Konuşmalar",
        .ai_newConversation: "Yeni sohbet",
        .ai_noConversations: "Henüz sohbet yok",
        .ai_untitled: "Başlıksız",
        .ai_pin: "Sabitle",
        .ai_unpin: "Sabitlemeyi kaldır",
        .ai_rename: "Yeniden adlandır",
        .ai_duplicate: "Çoğalt",

        .set_title: "Ayarlar",
        .set_ai: "AI",
        .set_general: "Genel",
        .set_about: "Hakkında",
        .set_aiDescription: "Değişiklikler otomatik kaydedilmiyor — Kaydet'e bas.",
        .set_apiKey: "API Anahtarı",
        .set_model: "Model",
        .set_active: "Aktif",
        .set_getApiKey: "API anahtarı al",
        .set_anthropic: "Anthropic Claude",
        .set_openai: "OpenAI",
        .set_ollama: "Ollama (Yerel)",
        .set_ollamaHint: "Ollama CLI kuruluysa otomatik kullanılır. Sadece model adını gir.",
        .set_launch_title: "Girişte başlat",
        .set_launch_body: "macOS açıldığında NeuraBar arka planda açılır.",
        .set_dataFolder: "Veri klasörü",
        .set_revealFolder: "Finder'da göster",
        .set_shortcuts: "Klavye kısayolları",
        .set_language: "Dil",
        .set_language_body: "Arayüz dili. \"Sistem\" macOS dilini takip eder.",
        .set_autoSaveNote: "Bu sekme otomatik kaydeder.",
        .set_sc_palette: "Komut paleti",
        .set_sc_settings: "Ayarlar",
        .set_sc_tabs: "Sekmeler arası geçiş",
        .set_sc_quit: "Çıkış",
        .set_sc_global: "NeuraBar'ı aç (genel)",

        .about_version: "%@ · macOS 26 Tahoe",
        .about_description: "Gününe eşlik eden menü çubuğu iş alanı.",
        .about_copyright: "© 2026 Bayram Eker"
    ]
}

/// Observable localization engine. Views that read through `@EnvironmentObject`
/// re-render automatically when the language changes.
final class Localization: ObservableObject {
    static let shared = Localization()

    @Published private(set) var language: SupportedLanguage = .en

    func apply(override: SupportedLanguage) {
        let resolved: SupportedLanguage
        switch override {
        case .auto:
            let code = Locale.current.language.languageCode?.identifier ?? "en"
            resolved = (code == "tr") ? .tr : .en
        case .en, .tr:
            resolved = override
        }
        if resolved != language { language = resolved }
    }

    func t(_ key: Loc) -> String {
        switch language {
        case .en, .auto:
            return Dict.en[key] ?? key.rawValue
        case .tr:
            return Dict.tr[key] ?? Dict.en[key] ?? key.rawValue
        }
    }

    func t(_ key: Loc, _ args: CVarArg...) -> String {
        String(format: t(key), arguments: args)
    }
}

// Convenience shortcut so callers can write `L.t(.key)` in complex expressions.
// NOTE: Views should prefer `@EnvironmentObject var l10n: Localization` so they
// re-render on language change. Use this only in non-View static contexts.
enum L {
    static func t(_ key: Loc) -> String { Localization.shared.t(key) }
    static func t(_ key: Loc, _ args: CVarArg...) -> String {
        String(format: Localization.shared.t(key), arguments: args)
    }
}
