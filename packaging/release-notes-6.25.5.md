# DropDrive 6.25.5 — Mac + Windows

## Mac: สั่งดาวน์โหลดผ่านเครื่องมือในแชท
- เพิ่มช่องทางสั่งงานในเครื่อง: วิเคราะห์ลิงก์ ดาวน์โหลด กำหนดชื่อและปลายทาง และตรวจความคืบหน้า/ข้อผิดพลาด
- เพิ่ม local MCP adapter สำหรับเชื่อมแชทโดยไม่ต้องคลิกหน้าจอ ตรวจไฟล์จริงหลังแอปรายงานว่างานเสร็จแล้ว
- ส่งคำสั่งเดิมซ้ำด้วย request ID เดิมไม่เพิ่มงานดาวน์โหลดซ้ำ รวมถึงหลังเปิดแอปใหม่
- รายงานงานที่ถูกยกเลิกหรือรอกู้คืนคิวตามจริง ไม่สั่งกู้คืนคิวแทนผู้ใช้
- บัญชี Google และ OAuth ยังจัดการภายใน DropDrive ไม่ส่งข้อมูลล็อกอินให้ MCP และไม่เปิดพอร์ตเครือข่าย
- เป็นฟีเจอร์ opt-in: การอัปเดตแอปอย่างเดียวไม่เปิดใช้งาน MCP หรือติดตั้งให้โปรแกรมอื่น ต้องติดตั้ง local adapter แยกตาม [คู่มือ](https://github.com/kpathipan/dropdrive/tree/v6.25.5/mcp)

## Windows
- ปล่อยหมายเลขเวอร์ชันเดียวกันพร้อม Mac พร้อมชุดทดสอบและตัวติดตั้ง Windows ใหม่
- ฟังก์ชันเดิมคงเดิม รุ่นนี้ **ยังไม่มี local MCP บน Windows** ไม่ได้อ้างว่าฟีเจอร์นี้เท่ากันทั้งสองระบบ

## การทดสอบและข้อจำกัด
- MCP บน Mac ทดสอบส่งลิงก์ Google Drive สาธารณะ ดาวน์โหลดจริง ตรวจจำนวนไฟล์/ไฟล์ค้าง และส่งคำสั่งซ้ำ พร้อมทดสอบเรียกเครื่องมือโดยตรงจากแชท
- ผลทดสอบดังกล่าวไม่ใช่การรับรองทุกบัญชีส่วนตัว ทุกเว็บไซต์ หรือการดาวน์โหลดวิดีโอ/MP3 ผ่าน MCP ครบทุกกรณี
- ข้อจำกัด Instagram ที่ต้นทางจำกัดอายุ/สิทธิ์ และรายงานปัญหาวางหลายลิงก์ซ้ำบน Mac ยังไม่ได้แก้ในรุ่นนี้ หากพบอาการให้วางทีละลิงก์
- Windows ยังมีช่องว่างการทดสอบล็อกอินหลายบัญชีจริงและการตรวจหน้าตาบางกรณี ไม่ใช่รุ่นรับรอง full feature parity
- Windows ยังไม่มีใบรับรองผู้เผยแพร่; Mac ใช้ใบรับรอง Apple Development เดิม ไม่ได้ notarize ตัวติดตั้งใหม่อาจแสดงคำเตือนของระบบ

Both packages come from the same source commit. This is a scoped maintenance
release, not a certification of complete cross-platform/provider parity.
Updates are checked every 24 hours, or manually in Settings. Let active
downloads finish before updating. Keep the previous installers for recovery;
never overwrite existing downloads or roll the published feed backwards.
