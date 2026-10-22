# R6 Camera 0.5 執行紀錄

開始：2026-10-22 22:50 Asia/Taipei。基線 `ed632563898a1ed2e10d7158f7b588a887c0039b`，分支 `codex/r6-0.4`。基線 GitHub run 39766785728 為 success；本機 Python 五項測試通過。Windows 無 Swift/Xcode，Swift 與原生 App 必須由 GitHub macOS/Xcode 27 驗證。

## 4:3 版面：已確認並實作，等待原生與實拍驗收

提案 [主畫面](design/0.5/01-main-43.png)、[Q](design/0.5/02-q-43.png)、[對照總圖](design/0.5/contact-sheet-43.png) 是可重現的設計圖，不是實際 App 截圖。中央 864×648，左右控制區，底部曝光列；沒有新增尚未實作的 AF 區域選項。人物與白框只是合成固定素材，不是模型準確度證據。

使用者已回覆「確認，依此版面實作」。中央 4:3 viewport，HUD/Q 側欄與右側刻度盤分置黑色控制區，Q live palette 位於中央取景下方，完整二級頁仍全螢幕。七種驅動 glyph 依 palette 寬度縮放保持同列可觸控。

原生預覽改 `resizeAspect`，styled／fixture 改 fit，`ViewfinderGeometry` 使用相同 aspect-fit 座標，letterbox 與左右側欄不觸發對焦。格線依實際影像範圍，水平儀與四邊拍攝回饋位於中央取景區。Vision 保留實際 CVPixelBuffer 尺寸，對焦由 output pixel rect→metadata→preview layer→capture device 轉換，不將影像點直接當 native preview 視角。

保留 `.photo` preset 與原最大照片尺寸請求，不強制 activeFormat 或把16:9 buffer拉伸成4:3。這消除 App 額外滿版裁切，不能憑介面保證完整 CMOS 或 RAW／各 virtual lens 光學視角完全一致。實際 buffer／檔案比例不相符時 fit 顯示完整來源且需明示驗收差異。[原始資料研究](research/photo-framing-43-0.5.md)。

## 本次獨立核心變更

- 依格式／品質策略／尺寸變更預備相同拍照資源，不逐張重做；重用 serial renderQueue 的 CIContext，維持既有完整尺寸風格與編碼品質，不增加同時工作數（最多 2 capture／合計 3）。
- `BurstProfile` 依本次配置的請求尺寸、格式、精確曝光需求、responsive 支援與曝光時間決定軟體請求上限。processed、已知 ≤24MP、非精確手動曝光且支援 responsive 時 H+/H/L 可請求 8/4/1；其餘維持 4/2/1 或受曝光時間限制。不得降低照片尺寸來取得較快分支。8/4/1 是測試中的請求上限，不是裝置實測能力。
- 保留單調時鐘、無補拍、就緒檢查與背壓；分開回報未就緒、緩衝滿與取消。介面顯示請求上限、實際回呼間隔平均速度與降速原因。
- 沒有開啟 fast prioritization 或 deferred。前者可能改變品質；後者需要 Photos proxy/final、權限與風格後處理的新管線，不能直接套用目前本地完整照片儲存流程。詳見 [原始資料研究](research/responsive-capture-0.5.md)。
- 標示請求尺寸上限，另顯示上張實際 processed 尺寸；精確手動曝光 `.speed` 路徑不保證最高解析度。沒有假稱 `maxPhotoDimensions` 等於交付尺寸。
- 部分資源回呼失敗仍保存成功的 JPEG 或 DNG，明確報不完整，不因 RAW 錯誤丟棄已成功的 JPEG；新增檔案落盤回歸測試。

## 鳥眼與交付限制

本版模型散布閘門仍 fail-closed，`docs/bird-release.json` 不會無證據改成可散布。已找到官方 CC BY 4.0 發布的 I-MuPPET 鴿子眼／頭權重，完成單檔完整校驗、靜態檢查及正確前處理的完整 ONNX／ORT CPU 數值比對。模型約237MB、Mac CPU中位數約1.7–1.8秒／張，不能當即時追焦或 iPhone 效能；Core ML仍遇到ROIAlign缺少converter。100張獨立圖片、iOS runtime整合及真機測速未完成。研究與候選見 [鳥眼打包研究](research/bird-bundling-0.5.md) 及 [實際JSON](research/imuppet-onnx-result-0.5.json)。驗證 IPA 不含鳥眼權重，不代表完整計畫已完成。

沒有 iPhone 真機可供此執行環境測試，連拍 10 秒的 95% 間隔偏差、實際鏡頭合焦、按鍵、水平儀方向、真實鳥眼準確度與推論延遲均不能宣稱通過。音量鍵仍可能觸發快門，沿用使用者接受的未解決項。

## 最終可交付驗證版

- App 來源 `be398da1054a6b8b21236c82f2aa44363da41f02`，版本0.5.0／build5，分支 `codex/r6-0.4`。後續研究／文件提交不改此 IPA 的來源。
- [GitHub build 39822660059](https://github.com/m2912kenny3643/camera/actions/runs/39822660059)：50項 Swift核心、51項 iOS單元、8項 Python與1個完整UI流程均通過；UI流程115.651秒。
- [實際六畫面](design/0.5/actual-ui-six.png)：中央4:3、側欄不觸發對焦、右側轉盤不覆蓋Q區、七個驅動glyph、SET／返回、曝光模式、水平儀與拍攝回饋已經自動化及截圖核對。固定素材不是辨識準確度證明。
- unsigned iPhone arm64 IPA 8,557,438 bytes，SHA256 `3bcb1f8e98bfbf874be9ec0dbd679aa99e63f2beaf3e28960c4105d416082d25`；需重新簽署後安裝。已核對 Info.plist、固定LandscapeRight、Mach-O arm64、執行位元、SOURCE-COMMIT、完整AGPL授權及模型內容。
- 含基礎Apple主體模型，不含BirdEyePose或I-MuPPET權重；完整鳥眼／真機驗收仍未完成。轉盤頂部刻度留白是截圖QA後的小修正，已重跑全部原生測試。
