# App Store Submission Assets

## Files in This Folder

- `description.txt` - All App Store copy (description, keywords, subtitle, etc.)
- `privacy-policy.html` - Now live at https://mikevincent.dev/privacy/
- `screenshots/` - Put your screenshots here

---

## Screenshot Instructions

### Required Size
Use **2880 x 1800** pixels (Retina 15" MacBook Pro resolution)

### How to Capture

1. Set your display to 1440 x 900 (or use a 2880x1800 window)
2. Resize Timer Fantasy window to fill the frame nicely
3. Press **Cmd + Shift + 4**, then **Space**, then click the window

Or use this script to resize the app window:
```bash
osascript -e 'tell application "Timer Fantasy" to set bounds of front window to {0, 0, 1440, 900}'
```

### Recommended Screenshots (capture these states)

1. **Idle state** - Show the time picker with a preset selected (e.g., 5m or 30m)
2. **Running timer** - Timer counting down, showing the analog clock face
3. **Multiple timers** - 2-3 timers running at different scales
4. **Watchface variety** - Show different clockface scales (5m, 60m, 8h)
5. **Settings popover** - Show the ellipsis menu with sound/loop options

### Tips
- Use different timer colors for visual variety
- Show timers at interesting times (not 00:00 or exactly on the minute)
- Dark backgrounds look great in App Store listings

---

## Before Submitting in Xcode

### Fix Copyright in Project Settings
1. Open TimerFantasy.xcodeproj in Xcode
2. Select the project in the navigator
3. Select the "TimerFantasy" target
4. Go to "Build Settings"
5. Search for "copyright"
6. Set "Human-Readable Copyright" to: `Copyright © 2026 Mike Vincent. All rights reserved.`

### Archive and Upload
1. Product > Archive
2. Window > Organizer
3. Select the archive > Distribute App
4. Choose "App Store Connect"
5. Follow the prompts

---

## App Store Connect Checklist

- [x] App name: Timer Fantasy
- [x] Subtitle: Analog Timers for Your Mac
- [x] Description: (from description.txt)
- [x] Keywords: (from description.txt)
- [x] What's New: Initial release.
- [ ] Screenshots: 1-10 at 2880x1800
- [x] Category: Productivity
- [x] Privacy Policy URL: https://mikevincent.dev/privacy/
- [x] Support URL: https://mikevincent.dev
- [x] Copyright: 2026 Mike Vincent
- [ ] Age Rating: Complete the questionnaire (4+)
- [ ] Archive and upload build from Xcode
