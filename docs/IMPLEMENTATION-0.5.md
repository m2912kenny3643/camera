# R6 Camera 0.5 執行紀錄

開始：2026-10-22 22:50 Asia/Taipei。基線 `ed632563898a1ed2e10d7158f7b588a887c0039b`，分支 `codex/r6-0.4`。基線 GitHub run 39766785728 為 success；本機 Python 五項測試通過。Windows 無 Swift/Xcode，Swift 與原生 App 必須由 GitHub macOS/Xcode 27 驗證。

## 4:3 版面：等待確認，尚未套入 App

提案 [主畫面](design/0.5/01-main-43.png)、[Q](design/0.5/02-q-43.png)、[對照總圖](design/0.5/contact-sheet-43.png) 是可重現的設計圖，不是實際 App 截圖。中央 864×648，左右控制區，底部曝光列；沒有新增尚未實作的 AF 區域選項。人物與白框只是合成固定素材，不是模型準確度證據。

依批准計畫要求，已送出版面確認問題；確認前不套用重大 UI 變更。共用取景／影像座標、真正完整 4:3、觸控側欄排除、各鏡頭 FOV、Q 及水平儀截圖仍待後續實作與驗收。

## 本次獨立核心變更

- 依格式／品質策略／尺寸變更預備相同拍照資源，不逐張重做；重用 serial renderQueue 的 CIContext，維持既有完整尺寸風格與編碼品質，不增加同時工作數（最多 2 capture／合計 3）。
- `BurstProfile` 依本次配置的請求尺寸、格式、精確曝光需求、responsive 支援與曝光時間決定軟體請求上限。processed、已知 ≤24MP、非精確手動曝光且支援 responsive 時 H+/H/L 可請求 8/4/1；其餘維持 4/2/1 或受曝光時間限制。不得降低照片尺寸來取得較快分支。8/4/1 是測試中的請求上限，不是裝置實測能力。
- 保留單調時鐘、無補拍、就緒檢查與背壓；分開回報未就緒、緩衝滿與取消。介面顯示請求上限、實際回呼間隔平均速度與降速原因。
- 沒有開啟 fast prioritization 或 deferred。前者可能改變品質；後者需要 Photos proxy/final、權限與風格後處理的新管線，不能直接套用目前本地完整照片儲存流程。詳見 [原始資料研究](research/responsive-capture-0.5.md)。
- 標示請求尺寸上限，另顯示上張實際 processed 尺寸；精確手動曝光 `.speed` 路徑不保證最高解析度。沒有假稱 `maxPhotoDimensions` 等於交付尺寸。
- 部分資源回呼失敗仍保存成功的 JPEG 或 DNG，明確報不完整，不因 RAW 錯誤丟棄已成功的 JPEG；新增檔案落盤回歸測試。

## 鳥眼與交付限制

本版模型散布閘門仍 fail-closed，`docs/bird-release.json` 不會無證據改成可散布。研究與候選見 `docs/research/bird-bundling-0.5.md`（研究完成後提供）。現有可下載驗證 IPA 不含鳥眼權重，不代表完整計畫已完成。

沒有 iPhone 真機可供此執行環境測試，連拍 10 秒的 95% 間隔偏差、實際鏡頭合焦、按鍵、水平儀方向、真實鳥眼準確度與推論延遲均不能宣稱通過。音量鍵仍可能觸發快門，沿用使用者接受的未解決項。
