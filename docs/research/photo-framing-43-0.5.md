# 0.5：4:3 照片取景、預覽與座標一致性研究

查證日期：2026-10-22。只新增研究文件，不改 App。研究開始時 4:3 UI 待確認；研究期間主代理通知使用者已確認 viewport + side rails 提案。UI 實作由主代理處理，本文件不把設計確認當成真機視角驗證。

## 結論與保證邊界

可以保證 **App 不再額外裁切／拉伸已收到的影像**，並用一致座標轉換讓 preview、Vision boxes 與 touch 對齊。不能僅憑 4:3 外框、CV buffer 寬高比或 photo dimensions，保證 video preview 與最終 processed / RAW 照片是完全相同視角，更不能稱為完整 CMOS。`.photo` 適合高解析 still，但不是完整感光元件讀出或固定比例的保證。[Apple .photo](https://developer.apple.com/documentation/avfoundation/avcapturesession/preset/photo)、[maxPhotoDimensions](https://developer.apple.com/documentation/avfoundation/avcapturephotooutput/maxphotodimensions)

## 現有管線的具體問題

| 層次 | 查證當下實作 | 影響 |
|---|---|---|
| 原生 preview | `AVCaptureVideoPreviewLayer.videoGravity = .resizeAspectFill` | 容器與來源比例不同時裁切 |
| 風格 preview | CV buffer → CIImage → CGImage，SwiftUI `.scaledToFill()` | 使用相同容器但仍可能裁切；通常蓋住 native preview |
| Vision | 對旋轉後 CV buffer 使用 `.up`，bounding box 轉 top-left normalized | 座標屬於 buffer，不是最終 still 或 layer |
| frameAspect | CVPixelBufferGetWidth / Height 經 onFrame 發布 | 只表示 buffer raster，不是照片比例／FOV metadata |
| overlay / touch | ViewfinderGeometry 為 aspect-fill rect；tap 反算 normalized buffer point | 單改 gravity 或外框會與既有 geometry 不一致 |
| AF device point | normalized buffer → 自訂 display → native layer captureDevicePointConverted | 隱含 buffer 和 native preview 可用相同 image rect；若兩路 crop / FOV 不同，此假設未經驗證 |

原始碼：[CameraPreview.swift:13](<C:/Users/m2912/OneDrive/Desktop/canon camera/R6Camera/UI/CameraPreview.swift:13>)、[CameraView.swift:70](<C:/Users/m2912/OneDrive/Desktop/canon camera/R6Camera/UI/CameraView.swift:70>)、[SubjectVision.swift:77](<C:/Users/m2912/OneDrive/Desktop/canon camera/R6Camera/Camera/SubjectVision.swift:77>)、[ViewfinderGeometry:213](<C:/Users/m2912/OneDrive/Desktop/canon camera/R6Camera/Core/SubjectTracker.swift:213>)、[CameraController focusOnImagePoint](<C:/Users/m2912/OneDrive/Desktop/canon camera/R6Camera/Camera/CameraController.swift:520>)。行號會隨主代理實作移動。

## 已查證的 Apple 契約

### .photo、activeFormat 與照片 dimensions

在 iOS，設定 `device.activeFormat` 會把 session preset 改為 `.inputPriority`；設定 `sessionPreset` 則由 session 控制並選取 activeFormat。**不能一邊宣稱維持 `.photo`，一邊手動強制 activeFormat 為某個4:3 video format**。高解析 still format 加上 VideoDataOutput 的 zoom / rotation / format 調整，也可能無法達到目標 video frame rate。[Apple activeFormat](https://developer.apple.com/documentation/avfoundation/avcapturedevice/activeformat)

`activeFormat.supportedMaxPhotoDimensions: [CMVideoDimensions]` 是照片可請求的最大尺寸列表。選 current format 裡最高4:3尺寸，可控制 request 的比例上限；若此值低於原本最高 request，必須視為解析度政策改變，不能靜默降級。若沒有4:3值，不應任意造一個尺寸。`maxPhotoDimensions` 必須符合列表值，交付可能較小；用 `AVCaptureResolvedPhotoSettings.photoDimensions` 和最終檔案尺寸驗證。[Apple supportedMaxPhotoDimensions](https://developer.apple.com/documentation/avfoundation/avcapturedevice/format/supportedmaxphotodimensions)、[Apple maxPhotoDimensions](https://developer.apple.com/documentation/avfoundation/avcapturephotooutput/maxphotodimensions)

4:3 判斷應使用整數交叉乘積或明確容差，處理 orientation 後長邊／短邊；不能用「24MP」名稱推導比例。照片 Exif orientation 需先納入 presentation width / height，RAW / processed 分別記錄。[Apple videoRotationAngle](https://developer.apple.com/documentation/avfoundation/avcaptureconnection/videorotationangle)

### VideoDataOutput 尺寸：不是任意裁切控制

`automaticallyConfiguresOutputBufferDimensions` 預設 true，系統可交付約螢幕大小的 preview buffers；`videoSettings` 可查實際配置。要手動設定 `deliversPreviewSizedOutputBuffers`，必須先關 automatic。這些屬性調整 buffer 尺寸，不能據此宣稱拿到更大感光元件視野。[Apple automatic dimensions](https://developer.apple.com/documentation/avfoundation/avcapturevideodataoutput/automaticallyconfiguresoutputbufferdimensions)、[Apple preview-sized buffers](https://developer.apple.com/documentation/avfoundation/avcapturevideodataoutput/deliverspreviewsizedoutputbuffers)

iOS16+ 可在 uncompressed videoSettings 設 width / height，但比例必須符合 activeFormat 經 connection orientation 校正後的比例，且不可大於 source；`deliversPreviewSizedOutputBuffers == true` 時不能改 width / height。違規會 exception。**16:9 source 不能硬塞4:3 width/height來補回上下畫面**。[Apple videoSettings](https://developer.apple.com/documentation/avfoundation/avcapturevideodataoutput/videosettings)

CV width / height 是 raster；若 sample 的 clean aperture / pixel aspect ratio 非預期，應記錄 format description，再用 `CMVideoFormatDescriptionGetPresentationDimensions(... usePixelAspectRatio: true, useCleanAperture: true)` 檢查 presentation aspect，不能假定永遠正方像素且沒有 aperture。[Apple presentation dimensions](https://developer.apple.com/documentation/coremedia/cmvideoformatdescriptiongetpresentationdimensions(_:usepixelaspectratio:usecleanaperture:))

### 可靠的座標橋接

`captureDevicePointConverted(fromLayerPoint:)` 接收**實際 layer bounds 的點**，回傳 device 的未旋轉 normalized 座標；會考量 layer size / gravity。反向可用 `layerPointConverted(fromCaptureDevicePoint:)`。因此直接點原生 preview 時應以 layer converter 為準，不再用猜測的比例換算。[Apple layer→device](https://developer.apple.com/documentation/avfoundation/avcapturevideopreviewlayer/capturedevicepointconverted(fromlayerpoint:))、[Apple device→layer](https://developer.apple.com/documentation/avfoundation/avcapturevideopreviewlayer/layerpointconverted(fromcapturedevicepoint:))

Vision / styled buffer 與原生 layer 之間可用共同 metadata coordinate system：

1. 把 top-left normalized Vision / buffer rectangle 按**該幀 CV width / height**換為 output pixel rectangle。
2. `videoOutput.metadataOutputRectConverted(fromOutputRect:)` 轉成未旋轉 normalized metadata rect；此 API 會處理 orientation、mirroring、scaling。
3. 用 `previewLayer.layerRectConverted(fromMetadataOutputRect:)` 轉到 native layer；反向用 `metadataOutputRectConverted(fromLayerRect:)` 再 `videoOutput.outputRectConverted(fromMetadataOutputRect:)`。

API output 座標是 pixel coordinate；不可直接把0…1 normalized Vision rect 當成 output rect，也不可把 Vision lower-left origin 原封不動傳入。點可透過明確的小矩形中心轉換，實作須測試邊界／尺寸，不把空 rectangle 的未記載行為當契約。[Apple output→metadata](https://developer.apple.com/documentation/avfoundation/avcaptureoutput/metadataoutputrectconverted(fromoutputrect:))、[Apple metadata→output](https://developer.apple.com/documentation/avfoundation/avcaptureoutput/outputrectconverted(frommetadataoutputrect:))、[Apple metadata→layer](https://developer.apple.com/documentation/avfoundation/avcapturevideopreviewlayer/layerrectconverted(frommetadataoutputrect:))

若顯示的是 styled buffer，overlay / touch 應直接共用該 buffer 的 fit transform，tap 先還原 output pixel point，再走上述 metadata/device 座標。不要先把它當原生 layer 點。這套 conversion 只處理 API 記載的座標轉換；不是 still-video 光學 FOV 校準，也不替不同鏡頭做視差或非線性畸變校正。

### 虛擬鏡頭、RAW 與 FOV 限制

`activePrimaryConstituent` 可觀察，會隨 zoom、曝光、focus 改變。`virtualDeviceSwitchOverVideoZoomFactors` 是各 constituent 在 FOV 相符附近可切換的 zoom factors，並非保證固定實體鏡頭。單以顯示的0.5×/1×/2×不能驗證同一來源。[Apple constituent](https://developer.apple.com/documentation/avfoundation/avcapturedevice/activeprimaryconstituent)、[Apple switch-over factors](https://developer.apple.com/documentation/avfoundation/avcapturedevice/virtualdeviceswitchovervideozoomfactors)

`isAutoVirtualDeviceFusionEnabled` 預設 true，但 RAW / brackets 例外；融合是否啟用取決於 zoom、light、focus，可查 resolved `isVirtualDeviceFusionEnabled`。因此 RAW 與 processed 不能直接推定完全相同投影。`photo.sourceDeviceType` 在一般 virtual capture 可能只回報 virtual type，不一定告訴實際 constituent；不可當成完整鏡頭證據。[Apple virtual fusion](https://developer.apple.com/documentation/avfoundation/avcapturephotosettings/isautovirtualdevicefusionenabled)、[Apple sourceDeviceType](https://developer.apple.com/documentation/avfoundation/avcapturephoto/sourcedevicetype)

`videoFieldOfView` 只是 format 的 horizontal FOV（可能為0未知）。照片的 content-aware distortion correction 另有設定，不能以單一 video FOV 數字證明 final photo 與 preview 相同幾何。本研究未查到能對所有 iPhone17 zoom / RAW / processed 組合保證「完整 CMOS 且逐像素對齊」的一個公開開關。[Apple videoFieldOfView](https://developer.apple.com/documentation/avfoundation/avcapturedevice/format/videofieldofview)、[Apple distortion correction](https://developer.apple.com/documentation/avfoundation/avcapturephotosettings/isautocontentawaredistortioncorrectionenabled)

## 最小可實作方案（工程建議）

1. 按確認提案放置4:3 viewport / side rails；native 改 `.resizeAspect`，styled / fixture 以 fit 顯示；geometry 亦同步改為 fit 的同一 imageRect。tap 落在 letterbox 應忽略，不能 clamp 成邊緣 AF；grid / feedback / box 必須說清楚畫在 viewport 還是實際 imageRect。[Apple resizeAspect](https://developer.apple.com/documentation/avfoundation/avlayervideogravity/resizeaspect)
2. 保留 `.photo`、既有品質與尺寸策略。從 current activeFormat 記錄 supported photo dimensions；僅在不靜默降解析的前提選4:3 request。**不強制 activeFormat、不任意指定 video width/height、不拉伸、不以輸出裁切偽造完整取景**。
3. 固定 LandscapeRight：沿用 RotationCoordinator 的實際角度，分別設定 native preview / VideoDataOutput / PhotoOutput。VideoDataOutput 是旋轉 pixels；PhotoOutput 是 Exif orientation，後者要依metadata解讀，不能再額外旋轉一次。[Apple rotation](https://developer.apple.com/documentation/avfoundation/avcaptureconnection/videorotationangle)
4. 每幀用 buffer size / aperture 和同配置的 geometry snapshot，不能先切換新aspect再搭舊styledFrame。原生與styled路徑需各驗證；native mapping 用layer conversion，buffer mapping用output conversion。切鏡頭／比例變化時清除舊 overlay，重新取得幾何。
5. 若 video 實際比例不是4:3，完整fit保留letterbox並顯示「預覽與照片視角待驗證」；不要用4:3框暗示畫面外像素已存在。即使兩者同為4:3，也只在真機標定通過後宣稱該配置視角一致。

## 真機驗收與保留未知

在腳架固定、平面格線／四角標記場景下，同時保存當次 CV buffer、native preview screenshot、styled preview、JPEG/HEIF、RAW/DNG。分鏡頭／切換點前後zoom、遠景／近距、明亮／低光、P／精確手動，記錄 uniqueID、時間、active format video dimensions、supported/max/resolved photo dimensions、buffer presentation dimensions、orientation/mirroring、zoom、active constituent、fusion flags。照片讀入後統一Exif orientation，再比較中心與四邊，而非只比aspect。檢查四角主體box、中央與邊緣tap AF、letterbox無反應、MF放大還原後geometry。

驗收結果分開列：① App 顯示無額外裁切／拉伸；② buffer／overlay／touch一致；③各配置 still-video framing偏差。①②可以邏輯／UI測試部分證明，③需真正相機資料。不能用模擬器fixture代替光學視角驗證。若RAW顯影與processed邊界有差異，保留原檔，明示差異；不能裁原檔來掩蓋。

以上是最小方案及驗收建議，沒有聲稱真機測量已完成。本機為Windows，已核對Apple官方DocC宣告／說明；未在Xcode27裝置上probe。後續SDK編譯與機型實測仍為交付門檻。
