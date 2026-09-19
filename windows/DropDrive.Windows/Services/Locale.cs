using System.Security.Cryptography;
using System.Text;
using Avalonia;

namespace DropDrive.Windows.Services;

public static class Locale
{
    public static bool IsEnglish { get; private set; }
    public static string Key(string text) => "L" + Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(text)))[..12];
    public static void Apply(bool english)
    {
        IsEnglish = english;
        if (Application.Current is not { } app) return;
        foreach (var pair in English) app.Resources[Key(pair.Key)] = english ? pair.Value : pair.Key;
    }
    public static string Text(string text) => IsEnglish ? English.GetValueOrDefault(text, text) : text;
    public static string Choose(string thai, string english) => IsEnglish ? english : thai;
    public static readonly IReadOnlyDictionary<string, string> English = new Dictionary<string, string>
    {
        ["Ctrl+Shift+D · เปิด DropDrive"] = "Ctrl+Shift+D · Open DropDrive",
        ["Drive, YouTube, TikTok, Facebook, Instagram · วางหลายลิงก์ได้"] = "Drive, YouTube, TikTok, Facebook, Instagram · Multiple links",
        ["กลาง"] = "Medium", ["การตั้งค่า"] = "Settings", ["การ์ด"] = "Cards", ["ขนาดการ์ด"] = "Card size",
        ["คัดลอกลิงก์"] = "Copy link", ["คำบรรยาย"] = "Subtitles", ["คิวดาวน์โหลด"] = "Downloads",
        ["คุณภาพและ MP3"] = "Quality and MP3", ["ค้นหาชื่อหรือเว็บไซต์"] = "Search name or website",
        ["ค้นหาชื่อไฟล์"] = "Search files", ["จบ เช่น 1:30"] = "End, e.g. 1:30", ["จำกัดความเร็ว"] = "Bandwidth",
        ["ชื่อไฟล์"] = "File name", ["ดาวน์โหลด"] = "Download", ["ดาวน์โหลดรายการที่เลือก"] = "Download selected items",
        ["ดาวน์โหลดอีกครั้ง"] = "Download again", ["ดาวน์โหลดใหม่"] = "New download", ["ตรวจรายการ"] = "Review",
        ["ตรวจรายการ / เลือกปลายทางใหม่"] = "Review / change destination", ["ตรวจหาอัปเดตตอนนี้"] = "Check for updates",
        ["ตรวจอัปเดตอัตโนมัติทุก 24 ชั่วโมง"] = "Check for updates every 24 hours", ["ตรวจแล้วลองใหม่"] = "Review and retry",
        ["ตัวเลือกเพิ่มเติม"] = "More options", ["ตามระบบ"] = "System",
        ["ติดตั้งอัปเดตเมื่อคิวดาวน์โหลดว่าง ไม่ขัดจังหวะงาน"] = "Updates install when idle, without interrupting downloads.",
        ["ทำงานต่อในถาดระบบเมื่อปิดหน้าต่าง"] = "Keep running in the system tray on close",
        ["ทุกอย่างพร้อมใช้งาน"] = "Everything is ready", ["ธีม"] = "Theme", ["บันทึกที่"] = "Save to",
        ["บันทึกภาพปกด้วย"] = "Save cover image", ["ประวัติ 100 รายการล่าสุด · ล้างประวัติไม่ลบไฟล์"] = "Last 100 downloads · Clearing history keeps your files",
        ["ปิดข้อความ"] = "Dismiss", ["ปิดตัวอย่าง"] = "Close preview", ["พร้อมใช้งาน"] = "Ready",
        ["พักคิว"] = "Pause queue", ["มืด"] = "Dark", ["ยกเลิก"] = "Cancel", ["ยังไม่มีประวัติการดาวน์โหลด"] = "No recent downloads",
        ["รวมในการดาวน์โหลดชุดนี้"] = "Include in batch", ["รับลิงก์จากมือถือ"] = "Send from phone",
        ["รับลิงก์ผ่านโฟลเดอร์ซิงก์"] = "Receive links from a synced folder", ["รายการ"] = "List",
        ["รายการที่ต้องตรวจสอบ"] = "Needs attention", ["รายการที่เน็ตหลุด ไดรฟ์ถูกถอด หรือดาวน์โหลดไม่สำเร็จ"] = "Disconnected network, missing drives and failed downloads",
        ["รูปแบบ"] = "Format", ["รูปแบบรายการ"] = "Layout", ["ลิงก์ดาวน์โหลด"] = "Download link", ["ล่าสุด"] = "Recent",
        ["ล้างที่เสร็จแล้ว"] = "Clear finished", ["ล้างประวัติ"] = "Clear history", ["ล้างลิงก์"] = "Clear link",
        ["วางลิงก์จากคลิปบอร์ด"] = "Paste link", ["วางลิงก์ที่ต้องการดาวน์โหลด"] = "Paste a download link",
        ["วิดีโอที่เปิดได้ทั่วไป · MP4"] = "Compatible video · MP4", ["วิเคราะห์"] = "Analyze",
        ["สถิติในเครื่อง"] = "Local statistics", ["สว่าง"] = "Light", ["หยุดชั่วคราว"] = "Paused",
        ["ออกจาก DropDrive"] = "Quit DropDrive", ["เคยดาวน์โหลดลิงก์นี้แล้ว เลือกรูปแบบใหม่หรือดาวน์โหลดซ้ำได้"] = "Previously downloaded. Choose a format or download again.",
        ["เปลี่ยน"] = "Change", ["เปลี่ยน⌄"] = "Change⌄", ["เปิด"] = "Open", ["เปิดพร้อม Windows"] = "Launch at login",
        ["เปิดโฟลเดอร์เมื่อดาวน์โหลดเสร็จ"] = "Open folder when finished", ["เปิดไฟล์"] = "Open file", ["เริ่ม เช่น 0:30"] = "Start, e.g. 0:30",
        ["เลือกการ์ดแล้วกด Space เพื่อดูภาพตัวอย่าง"] = "Focus a file and press Space to preview",
        ["เลือกดาวน์โหลดเฉพาะไฟล์"] = "Choose files", ["เลือกทั้งหมด"] = "Select all", ["เลือกเฉพาะใหม่ / เปลี่ยนแปลง"] = "Select new / changed",
        ["เลือกโฟลเดอร์ OneDrive หรือ iCloud ที่ซิงก์กับมือถือ แล้วบันทึกลิงก์เป็น .txt / .url / .webloc แอปจะรับมาตรวจรายการ และย้ายไฟล์ลิงก์ที่รับแล้วไป Processed"] = "Choose a OneDrive or iCloud folder synced with your phone. Save links as .txt / .url / .webloc. Received links appear for review; processed inputs move to Processed.",
        ["เลือกโฟลเดอร์ซิงก์"] = "Choose synced folder", ["เลื่อนคิวขึ้น"] = "Move up", ["เลื่อนคิวลง"] = "Move down",
        ["เล็ก"] = "Small", ["เวลาสิ้นสุด"] = "End time", ["เวลาเริ่ม"] = "Start time", ["เสียงแจ้งเตือน"] = "Notification sound",
        ["เอาออกจากคิว"] = "Remove from queue", ["แจ้งเตือนเมื่อดาวน์โหลดเสร็จ"] = "Notify when finished",
        ["แยกไฟล์ตามบท (ถ้ามี)"] = "Split chapters (if available)", ["แสดงใน Explorer"] = "Show in Explorer",
        ["โฟลเดอร์ดาวน์โหลด"] = "Download folder", ["ใหญ่"] = "Large", ["ไม่จำกัด"] = "Unlimited",
        ["ภาษา"] = "Language", ["เข้าคิว"] = "Add to queue", ["เดินคิวต่อ"] = "Resume queue",
        ["อัตโนมัติ"] = "Automatic", ["คุณภาพสูงสุด"] = "Best quality", ["ไฟล์เล็ก · 480p"] = "Small · 480p", ["เสียง MP3"] = "Audio MP3",
        ["ไม่บันทึกคำบรรยาย"] = "No subtitles", ["ไฟล์คำบรรยายแยก"] = "Separate subtitles", ["ฝังคำบรรยายในวิดีโอ"] = "Embed subtitles",
        ["พร้อม"] = "Ready", ["รอคิว"] = "Queued", ["กำลังเริ่ม"] = "Starting", ["กำลังวิเคราะห์"] = "Analyzing",
        ["กำลังดาวน์โหลด"] = "Downloading", ["เสร็จแล้ว"] = "Complete", ["ไม่สำเร็จ"] = "Failed", ["ยกเลิกแล้ว"] = "Cancelled",
        ["ใหม่"] = "New", ["โหลดแล้ว"] = "Downloaded", ["เปลี่ยนแปลง"] = "Changed", ["เลือกโฟลเดอร์อื่น…"] = "Choose another folder…",
        ["ยังไม่ได้เลือกโฟลเดอร์ซิงก์"] = "No synced folder selected", ["ไม่พบรายการที่ค้นหา"] = "No matching downloads",
        ["กำลังบันทึกไฟล์"] = "Saving file", ["กำลังรวมไฟล์วิดีโอ…"] = "Merging video…", ["กำลังแปลงเป็น MP3…"] = "Converting to MP3…",
        ["บันทึกเป็น MP3 แล้ว"] = "Saved as MP3", ["บันทึกในโฟลเดอร์ปลายทางแล้ว"] = "Saved to destination folder",
        ["ลิงก์นี้อยู่ในคิวแล้ว"] = "This link is already queued", ["เลือกอย่างน้อย 1 ไฟล์"] = "Select at least one file",
        ["วางลิงก์เว็บที่ถูกต้องก่อน"] = "Paste a valid web link first", ["คัดลอกลิงก์แล้ว"] = "Link copied",
        ["ไม่พบไฟล์ อาจถูกย้ายหรือลบแล้ว"] = "File not found. It may have been moved or deleted.",
        ["พื้นที่ว่างไม่เพียงพอสำหรับการดาวน์โหลดนี้"] = "Not enough free space for this download.",
        ["ไม่พบโฟลเดอร์ปลายทาง เชื่อมต่อไดรฟ์หรือเลือกโฟลเดอร์ใหม่"] = "Destination unavailable. Reconnect the drive or choose another folder.",
        ["การเชื่อมต่อขาดหายหรือไฟล์ไม่พร้อม กดลองใหม่"] = "Connection lost or file unavailable. Please retry.",
        ["เวลาสิ้นสุดต้องมากกว่าเวลาเริ่ม"] = "End time must be after start time.",
        ["เวลาไม่ถูกต้อง เช่น 0:30 หรือ 90"] = "Invalid time. Use 0:30 or 90, for example."
    };
}
