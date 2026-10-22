# 0.5 responsive still capture：原始資料查證與最小方案

查證日期：2026-10-22。範圍：iPhone 17 / iOS 27、真正的 `AVCapturePhotoOutput` 照片；只研究，不修改 App 或 workflow。以下「上限」是請求值，不代表交付解析度或保證 fps。

## 結論

保留現有解析度請求、品質策略、RAW 原檔、風格及手動曝光時，最安全的第一步是**預備相同拍照資源、重用背景 CIContext，並只在低風險條件提高軟體請求上限**。目前 responsive / ZSL 已開啟；重新開一次不會解除 App 的 cadence 或工作數限制。Deferred 可以改善系統處理阻塞，但不是現有儲存管線的一行開關；fast prioritization 會改變品質，嚴格保留品質時不採用。[現有設定](<C:/Users/m2912/OneDrive/Desktop/canon camera/R6Camera/Camera/CameraController.swift:259>)、[Apple CIContext](https://developer.apple.com/documentation/coreimage/cicontext)、[WWDC26/304](https://developer.apple.com/videos/play/wwdc2026/304/?time=581)

本研究沒有真機吞吐量資料，不能承諾 8 fps，更不能承諾 Canon 的 40 fps。照片 API 的交付與預覽 video frame rate 不同；本方案不擷取 video frames 代替照片。

## 本機已確認的行為

| 項目 | 現況與影響 | 原始碼 |
|---|---|---|
| 連拍請求 | H+ / H / L 為 4 / 2 / 1 fps | [CameraSettings.swift:41](<C:/Users/m2912/OneDrive/Desktop/canon camera/R6Camera/Core/CameraSettings.swift:41>) |
| 曝光時間界限 | interval 至少為 exposure + 0.03 秒；未就緒退避 0.05 秒；一次過慢會將這次長按的 interval 永久拉長 | [BurstCadence.swift:12](<C:/Users/m2912/OneDrive/Desktop/canon camera/R6Camera/Core/BurstCadence.swift:12>) |
| 系統能力 | 支援才開 responsive / ZSL，output 的品質上限設 `.quality` | [CameraController.swift:259](<C:/Users/m2912/OneDrive/Desktop/canon camera/R6Camera/Camera/CameraController.swift:259>) |
| 每張設定 | 請求 active format 支援的最大 dimensions；需精確曝光時 `.speed`，否則 `.balanced` | [CameraController.swift:629](<C:/Users/m2912/OneDrive/Desktop/canon camera/R6Camera/Camera/CameraController.swift:629>) |
| 背壓 | `.ready` 且 capture jobs < 2、jobs + rendering < 3 才收新請求 | [CameraController.swift:614](<C:/Users/m2912/OneDrive/Desktop/canon camera/R6Camera/Camera/CameraController.swift:614>) |
| App 後製 | 背景完整尺寸風格渲染與編碼，每張重新建立 CIContext；渲染佔總工作數 | [CameraController.swift:674](<C:/Users/m2912/OneDrive/Desktop/canon camera/R6Camera/Camera/CameraController.swift:674>)、[PhotoRenderer.swift:27](<C:/Users/m2912/OneDrive/Desktop/canon camera/R6Camera/Camera/PhotoRenderer.swift:27>) |
| 儲存契約 | 先存 App 完整 processed / RAW，再後製，最後以 addOnly 存 `.photo` / `.alternatePhoto`；沒有 proxy callback | [CameraController.swift:685](<C:/Users/m2912/OneDrive/Desktop/canon camera/R6Camera/Camera/CameraController.swift:685>)、[PhotoJob:764](<C:/Users/m2912/OneDrive/Desktop/canon camera/R6Camera/Camera/CameraController.swift:764>) |

這些是查證當下的工作樹位置，後續實作可能移動行號。既有 fps HUD 用 `didCapturePhotoFor` 事件時間差，不應改成計數送出的 requests。[CameraController.swift:633](<C:/Users/m2912/OneDrive/Desktop/canon camera/R6Camera/Camera/CameraController.swift:633>)

## Apple 公開 API 與適用條件

以下能力從 iOS 17 提供；iOS 27 仍需依當前 output / format 執行能力檢查，不能只以機型推定。精確 Swift 名稱：

| 能力 | 檢查 / 設定 | 說明 |
|---|---|---|
| 重疊照片 capture / processing | [`isResponsiveCaptureSupported`](https://developer.apple.com/documentation/avfoundation/avcapturephotooutput/isresponsivecapturesupported) / [`isResponsiveCaptureEnabled`](https://developer.apple.com/documentation/avfoundation/avcapturephotooutput/isresponsivecaptureenabled) | capture 階段完成即可開始下一張，並不縮短每張 processing；以 [`captureReadiness`](https://developer.apple.com/documentation/avfoundation/avcapturephotooutput/capturereadiness-swift.property) 管控新請求 |
| 減少按鍵到曝光延遲 | [`isZeroShutterLagSupported`](https://developer.apple.com/documentation/avfoundation/avcapturephotooutput/iszeroshutterlagsupported) / [`isZeroShutterLagEnabled`](https://developer.apple.com/documentation/avfoundation/avcapturephotooutput/iszeroshutterlagenabled) | ZSL 不等於持續照片吞吐量保證 |
| 自動品質換速度 | [`isFastCapturePrioritizationSupported`](https://developer.apple.com/documentation/avfoundation/avcapturephotooutput/isfastcaptureprioritizationsupported) / [`isFastCapturePrioritizationEnabled`](https://developer.apple.com/documentation/avfoundation/avcapturephotooutput/isfastcaptureprioritizationenabled) | 不符合「品質策略完全不變」的預設目標 |
| 延後最終處理 | [`isAutoDeferredPhotoDeliverySupported`](https://developer.apple.com/documentation/avfoundation/avcapturephotooutput/isautodeferredphotodeliverysupported) / [`isAutoDeferredPhotoDeliveryEnabled`](https://developer.apple.com/documentation/avfoundation/avcapturephotooutput/isautodeferredphotodeliveryenabled) | 啟動 session 前設定；不支援卻設 true 會產生 exception；變更需要較長 pipeline 重設 |

WWDC26/304 的關鍵限制：`.photo` preset 才支援 24/48MP；12MP 可用三種品質，48MP 需 balanced 或 quality，18/24MP 需 quality。Responsive 重疊處理；fast prioritization 在快速連拍時由 quality 調為 balanced。iOS 27 的新增行為是 iPhone 16/17 的 balanced fast captures 也能 deferred，並非新增固定高速照片 fps。[WWDC26/304，09:41 起](https://developer.apple.com/videos/play/wwdc2026/304/?time=581)

`maxPhotoDimensions` 必須是 active format 的支援值；交付可以較小，所以保持 request 不等於保證每張相同解析度。記錄 `AVCaptureResolvedPhotoSettings` / 最終檔案尺寸，UI 標「解析度上限」。[Apple maxPhotoDimensions](https://developer.apple.com/documentation/avfoundation/avcapturephotooutput/maxphotodimensions)

精確手動 ISO / shutter 與 Apple Fusion 有明確取捨：Apple 說明 `.balanced` / `.quality` 不保證遵守手動曝光，需 `.speed`。因此**不能為速度或 24MP 而偷偷切換現有精確曝光政策**；目前 `.speed` ＋最大 dimensions 也不能保證取得 48MP。[WWDC26 Camera Group Lab，13:47](https://developer.apple.com/videos/play/wwdc2026/8018/?time=827)

## 不改照片內容的可實作準備

1. 在啟用鏡頭／變更格式或曝光政策後，用與實際 capture 一致的 settings 預備資源：`photoOutput.setPreparedPhotoSettingsArray([prepareSettings], completionHandler: ...)`。包含相同 dimensions、codec / RAW 配對及 quality；實際拍照仍建立新 settings，不重用 prepare object。API 可預備 RAW buffers；完成回呼不在 main；若 session 未啟動，回呼會等啟動與準備完成。只在配置變更時做，不每張做。[Apple API](https://developer.apple.com/documentation/avfoundation/avcapturephotooutput/setpreparedphotosettingsarray(_:completionhandler:))
2. 讓串行 renderQueue 重用一個 CIContext，保持現有濾鏡參數、全尺寸輸出、metadata 與編碼品質。Apple 說 context 內含 kernel / buffer caches，不建議大量建立；CIContext 可跨執行緒使用，但可變 CIFilter 不能共用。[Apple CIContext](https://developer.apple.com/documentation/coreimage/cicontext)
3. 保留 bounded jobs、取消、原檔優先寫入與失敗保留策略。提高 admission ceiling 只能移除人為等待；相機 processing、RAW、完整尺寸 render / encode 仍可能使背壓更頻繁。這是根據本機管線的工程推論，不是 Apple 吞吐量保證。[現有 capture / render](<C:/Users/m2912/OneDrive/Desktop/canon camera/R6Camera/Camera/CameraController.swift:610>)

## Deferred proxy 的正確資料契約與目前阻擋

必要 callback（iOS 17+）：

```swift
func photoOutput(_ output: AVCapturePhotoOutput,
                 didFinishCapturingDeferredPhotoProxy proxy: AVCaptureDeferredPhotoProxy?,
                 error: Error?) {
    // Handle error / nil; obtain proxy.fileDataRepresentation().
    // Promptly import the unmodified data in a PHPhotoLibrary change block:
    // PHAssetCreationRequest.forAsset().addResource(with: .photoProxy, data: data, options: nil)
}
```

這是契約示意，未在本機 Windows 編譯。缺少此 delegate method 卻啟用 deferred，`capturePhoto` 會 exception。proxy 要儘快送入 Photos，否則系統清理未採用 intermediates 會造成資料風險；Photos 的中間資料不對 App 公開。只把 proxy 存 App 內並不能得到本機完整最終檔案。[Apple callback](https://developer.apple.com/documentation/avfoundation/avcapturephotocapturedelegate/photooutput(_:didfinishcapturingdeferredphotoproxy:error:))、[Apple proxy](https://developer.apple.com/documentation/avfoundation/avcapturedeferredphotoproxy)

`.photoProxy` 是專用 resource role；一般完整照片不能冒充 proxy。`addResource(with:data:options:)` 要放在 Photos change block；組合無效時 completion 回報錯誤。[Apple resource](https://developer.apple.com/documentation/photos/phassetresourcetype/photoproxy)、[Apple addResource](https://developer.apple.com/documentation/photos/phassetcreationrequest/addresource(with:data:options:))

還需同時處理 proxy 與一般 processed 回呼；deferred 為 output 自動選擇，沒有每張 opt-in/out。只寫入需要 write permission，顯示／修改 final 需 read permission。proxy 上預先套濾鏡或改 metadata 不會套到最終照片，必須取得 final 後走 PhotoKit adjustment；degraded preview 不是最終交付。[WWDC23/10105，deferred 部分](https://developer.apple.com/videos/play/wwdc2023/10105/)

因此本版不開 deferred：現有 addOnly 權限、App 本地最終照片／分享及每張風格都需要重新設計。研究未查得足以保證此 App RAW+JPEG 請求與 deferred 組合的官方逐項契約；不可推定 RAW 會變成 proxy，也不可將缺 RAW 當成功。若日後採用，應獨立保留 RAW 路徑並以真機完整驗證後才開放。[現有 PhotoJob](<C:/Users/m2912/OneDrive/Desktop/canon camera/R6Camera/Camera/CameraController.swift:764>)

## 對預定 0.5 最小實作的審核

**可接受的保守範圍（建議，未實測）**：不開 fast / deferred、不增加 capture 2 / total 3；重用 CIContext。僅 `isResponsiveCaptureSupported && processed && requestedPixels <= 24_000_000 && !requiresExactExposure` 使用 H+ / H / L **請求上限 8 / 4 / 1**，其他維持 4 / 2 / 1。這組數字是產品的軟體 ceiling，沒有 Apple 保證；以 HUD 同時標明「請求上限／實測」，未真機測試前須明示。[原有上限](<C:/Users/m2912/OneDrive/Desktop/canon camera/R6Camera/Core/CameraSettings.swift:41>)、[原有背壓](<C:/Users/m2912/OneDrive/Desktop/canon camera/R6Camera/Camera/CameraController.swift:614>)

具體風險與界限：

- 門檻採**本次 request** 的 `Int64(width) * Int64(height)`，不能拿上次 resolved 尺寸推定本次低解析；不能為通過門檻降低原有 dimensions。iPhone 17 若當前請求最大 48MP，這條件自然維持原速。
- 24MP 門檻並不代表 balanced 交付24MP；保留品質政策時應如實呈現上限／resolved。手動及 RAW 不提高 admission ceiling，原 RAW 欄位缺失必須失敗，不能顯示成功。[Apple dimensions](https://developer.apple.com/documentation/avfoundation/avcapturephotooutput/maxphotodimensions)、[曝光契約](https://developer.apple.com/videos/play/wwdc2026/8018/?time=827)
- 既有 cadence 只減速不恢復，一次 stall 後這次長按可能持續偏慢。首版保留屬保守選擇，但不能把設定8解讀成已達8；未來若要恢復，須另做穩定、無補拍隊列的 bounded adaptation。[BurstCadence.swift:25](<C:/Users/m2912/OneDrive/Desktop/canon camera/R6Camera/Core/BurstCadence.swift:25>)
- CIContext 重用不證明 GPU / encoder 或 Photos 成為非瓶頸；不擴工作數可避免無界排隊，實際改善可能只有首張或低負載場景。[Apple CIContext](https://developer.apple.com/documentation/coreimage/cicontext)

真機驗收最低條件：同鏡頭、光線、實際曝光、dimensions request、codec、風格做前後比較；分 processed / RAW、P / 精確手動、明亮 / 低光、10秒長按；記錄 request、曝光事件、完成、render/write 用時、blocked 原因、resolved/file dimensions、EXIF shutter/ISO、DNG 數量、峰值記憶體及熱狀態。每個成功 RAW+JPEG 都應有兩檔；停止長按不得繼續排隊補拍。模擬器與 CI 僅驗證控制邏輯／編譯，不得用來宣稱相機 fps。這是本研究建議的驗收方法，沒有聲稱已執行。

## 證據邊界

已查 Apple 官方 WWDC26/304、WWDC26/8018、WWDC23/10105 與當前 DocC Swift declarations（對應 `/tutorials/data/documentation/...json`）；Windows 沒有本地 Xcode27 SDK headers，也未執行裝置 API probe。未確認的機型／鏡頭／RAW 組合用 runtime support checks 和真機測試處理，不外推整個 iPhone17 系列。此文件只新增研究資料。
