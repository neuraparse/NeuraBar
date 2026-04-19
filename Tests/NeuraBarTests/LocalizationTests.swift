import XCTest
@testable import NeuraBar

final class LocalizationTests: XCTestCase {

    func testEnglishLookup() {
        let l = Localization()
        l.apply(override: .en)
        XCTAssertEqual(l.language, .en)
        XCTAssertEqual(l.t(.save), "Save")
        XCTAssertEqual(l.t(.tab_todos), "Tasks")
    }

    func testTurkishLookup() {
        let l = Localization()
        l.apply(override: .tr)
        XCTAssertEqual(l.language, .tr)
        XCTAssertEqual(l.t(.save), "Kaydet")
        XCTAssertEqual(l.t(.tab_todos), "Görevler")
    }

    func testFormattedStringsWithSingleArg() {
        let l = Localization()
        l.apply(override: .en)
        let str = l.t(.ai_emptyDesktopHint, "Claude Desktop")
        XCTAssertTrue(str.contains("Claude Desktop"),
                      "Expected Claude Desktop substitution, got \(str)")
    }

    func testFormattedStringsWithMultipleArgs() {
        let l = Localization()
        l.apply(override: .en)
        let str = l.t(.ai_picker_hint, 2, 1, 3)
        XCTAssertTrue(str.contains("2"))
        XCTAssertTrue(str.contains("1"))
        XCTAssertTrue(str.contains("3"))
    }

    func testTurkishFallsBackToEnglishWhenMissing() {
        // Every key has an EN translation, so even if a TR dict were missing
        // some, the fallback path exists. We exercise via a real TR key.
        let l = Localization()
        l.apply(override: .tr)
        XCTAssertNotEqual(l.t(.appTagline), Loc.appTagline.rawValue,
                          "appTagline should be resolved, not echoed as raw key")
    }

    func testAutoResolvesToSupportedLanguage() {
        let l = Localization()
        l.apply(override: .auto)
        XCTAssertTrue(l.language == .en || l.language == .tr,
                      "auto should resolve to en or tr")
    }

    func testApplyPublishesLanguageChange() {
        let l = Localization()
        l.apply(override: .en)
        var observed: SupportedLanguage?
        let cancel = l.$language.sink { observed = $0 }
        l.apply(override: .tr)
        XCTAssertEqual(observed, .tr)
        cancel.cancel()
    }

    /// Every declared Loc key must have at least an English translation —
    /// otherwise t() would echo the raw key name to users.
    func testEveryLocKeyHasEnglishTranslation() {
        let l = Localization()
        l.apply(override: .en)
        let allCases: [Loc] = [
            .appName, .appTagline,
            .subtitle_todos, .subtitle_focus, .subtitle_shortcuts, .subtitle_automate,
            .subtitle_clipboard, .subtitle_notes, .subtitle_record, .subtitle_system, .subtitle_ai,
            .tab_todos, .tab_focus, .tab_shortcuts, .tab_automate,
            .tab_clipboard, .tab_notes, .tab_record, .tab_system, .tab_ai,
            .save, .cancel, .close, .add, .remove, .delete, .edit, .done,
            .search, .loading, .thinking, .stop, .retry, .tryAgain, .refresh,
            .copied, .copy, .commandPalette, .settings, .quit,
            .palette_searchPlaceholder, .palette_noResults,
            .palette_section_tab, .palette_section_todo, .palette_section_note,
            .palette_section_shortcut, .palette_section_clip, .palette_section_action,
            .ai_providers_emptyTitle, .set_title, .set_ai, .set_general, .set_about,
            .about_version, .about_description, .about_copyright,
            .record_audioStart, .record_screenStart, .record_stop,
            .record_clickToStart, .record_empty, .set_sc_global,
            .todo_allDone, .todo_doneCountSuffix, .todo_tip,
            .todo_priority, .todo_priority_low, .todo_priority_normal, .todo_priority_high,
            .todo_dueToday, .todo_dueTomorrow, .todo_dueNextWeek, .todo_dueClear,
            .todo_markDone, .todo_markActive, .todo_noMatch,
            .todo_group_overdue, .todo_group_today, .todo_group_tomorrow,
            .todo_group_thisWeek, .todo_group_later, .todo_group_noDate, .todo_group_completed,
            .shortcut_pin, .shortcut_unpin, .shortcut_launches,
            .shortcut_edit, .shortcut_copyPath, .shortcut_importApps,
            .shortcut_dropHere, .shortcut_dropHint,
            .focus_mode_classic, .focus_mode_extended, .focus_mode_short,
            .focus_mode_deep, .focus_mode_custom,
            .focus_skip, .focus_extend5, .focus_endsAt,
            .focus_stat_streak, .focus_stat_sessionsToday, .focus_stat_focusTime,
            .focus_autoBreak, .focus_autoFocus, .focus_dailyGoal,
            .focus_custom_title, .focus_custom_focus,
            .focus_custom_shortBreak, .focus_custom_longBreak,
            .ai_conversations, .ai_newConversation, .ai_noConversations,
            .ai_untitled, .ai_pin, .ai_unpin, .ai_rename, .ai_duplicate,
            .sys_status_ok, .sys_status_warning, .sys_status_critical,
            .sys_configure, .sys_thresholds, .sys_notify, .sys_alert_title,
            .record_opt_mic, .record_opt_cursor, .record_opt_notify,
            .record_input, .record_savedToast,
            .record_notif_audioSaved, .record_notif_screenSaved,
            .clip_captured,
            .record_src_title, .record_src_subtitle,
            .record_src_fullScreen, .record_src_fullScreen_hint,
            .record_src_area, .record_src_area_hint,
            .record_src_systemPicker, .record_src_systemPicker_hint,
            .perm_allow, .perm_openSettings,
            .perm_screen_title, .perm_screen_request_body, .perm_screen_denied_body,
            .perm_mic_title, .perm_mic_request_body, .perm_mic_denied_body,
            .perm_restart_title, .perm_restart_body, .perm_restart_cta,
            .data_loc_title, .data_loc_explanation, .data_loc_current,
            .data_loc_local, .data_loc_icloud, .data_loc_gdrive, .data_loc_custom,
            .data_loc_notAvailable, .data_loc_pickFolder,
            .data_loc_migrated, .data_loc_switched
        ]
        for key in allCases {
            let value = l.t(key)
            XCTAssertNotEqual(value, key.rawValue,
                              "Missing English translation for \(key.rawValue)")
            XCTAssertFalse(value.isEmpty, "Empty English translation for \(key.rawValue)")
        }
    }
}

import Combine
