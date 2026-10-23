# R6 Camera

原生 Swift iPhone 相機，參考 EOS R6 Mark III 的拍攝資訊與 Q／MENU 操作。
目標裝置：iPhone 17 標準版、iOS 27。這是獨立專案，並非 Canon 官方 App。

## 0.8.1 硬體按鍵接收路徑修訂

已隨 App 封裝 Android NeoFocus 的固定 320×320 `bird-eye.onnx`，使用 ONNX Runtime 1.24.2 CPU 離線推論，不需安裝後下載。來源、雜湊、模型卡及 AGPL／MIT 授權脈絡見 [散布證據](docs/research/android-bird-0.7.md)。本版走公開完整來源的非商業研究功能測試路線，未宣稱商業權利或正式準確度合格。

主體選「鳥類」優先使用專用模型；觸控前基本 AF＋白色候選框，選鳥後唯一藍框依眼睛→觀測頭部→身體降級。眼點超過250ms沒有模型校正即移除；縮放或重新選取後拒絕舊結果。MENU → AF →「鳥眼模型功能測試」可查看實際固定照片推論及分享 JSON。遮眼素材是人工遮擋衍生圖，遠距群鳥漏檢仍保留，不能當成100張準確率驗收。

連拍同次長按只在持續受阻時降檔、不再回升或補拍。未校準採 H+4／H2／L1 張/s保守請求上限，實際速度仍受曝光與就緒限制。MENU → 設定 →「連拍穩定速度校準」會明示實拍與存檔；開啟鳥眼並依提示每段長按至少10秒，連續三段通過才按配置保存。H+依能力測12／10／8／6／4／2／1、H測6／4／2／1；不改格式、解析度或畫質。逐張時間可匯出JSON。

保留已確認4:3取景、置中水平儀、圓弧轉盤與曝光模式。真機鳥眼延遲、100張獨立圖準確度、鳥眼負載下穩定連拍、合焦、溫度及持續使用仍須實測；模擬器不替代真機。

## GitHub 編成 IPA

1. Push 到 `main`／`codex/r6-0.4`，或在 Actions → **Build iPhone IPA** → **Run workflow**。
2. 工作流程下載 Apple 主體偵測模型、產生 Xcode 專案、執行測試並編譯。
3. 全部測試成功後下載 **R6Camera-0.8-focus-areas-IPA** artifact，解壓取得 `.ipa`。
4. 使用相容的側載工具重新簽署後安裝；下載的 IPA 不能直接永久安裝。
   免費帳號的簽署有效期與 App 數量限制依 Apple 和側載工具規定。

CI 使用 `xcode-27` runner 和 `/Applications/Xcode_27.0.app`。
若 GitHub 尚未對帳號提供此 runner，需選用含相同 SDK 的 macOS runner。
最低部署版本 18.0，使用公開 API，目標真機為 iOS 27。
本專案不含登入、後端或上傳影像功能；所有主體推論在手機執行。

## 0.3 改版操作

- 固定橫向：相機鍵在上緣、Dynamic Island 左側、USB-C 右側；Q、MENU 與回放同方向。
- **0.8.0 兩段快門預設開啟**（保留已儲存的關閉）；MENU → 設定可切換。0.8.0 的 UIWindow 接收方式經真機回報無效，0.8.1 改回取景內容 view，並在 MENU／回放／巢狀診斷頁移轉同一接收器。浮層啟用時返回拍攝並對焦，確認頁面返回才拍；浮層有效期間可重複全按，關閉後保留 300ms，連拍放開停止。浮層不是原始半按事件，不能可靠辨別相機鍵與音量減，期間音量減仍可能拍攝；已啟用的浮層也不保證每次輕按重新回呼。不支援控制浮層時取景頁沿用一般硬體快門。事件 JSON 加入接收宿主與真正 SDK 回呼計數（不含模擬注入），零回呼不能當作已接收到按鍵；0.8.1 真機返回與系統相機誤啟動仍待驗證，見 [接收路徑與真機測試](docs/delivery/shutter-routing-0.8.1.md)。未新增側鍵縮放。
- **八種對焦區域**：取景圖示、Q 或 AF MENU 選擇重點、單點、擴展四點／環繞、彈性區域 1–3、全區域；SET 套用、返回取消。點選區域內主體、拖曳框移動、兩指縮放，彈性框可改寬高／置中／重設。全區域追蹤預設開啟，關閉則限制區域內追蹤；A+ 使用全區域，MF 不驅動 AF。區域會實際篩選主體並指定 iPhone 鏡頭對焦點，並非 Canon 感測器對焦點陣列。
- 螢幕右側倍率按鈕展開部分圓弧轉盤；下滑放大、上滑縮小，捏合可調倍率。轉盤刻度與文字共用同一圓心。
- 觸控前使用系統基本連續自動對焦，最多一個白色候選框；白框座標不控制對焦點。沒有候選不畫框。
- 點中主體後，一個藍框持續追焦，使用眼睛→觀測到的頭部區域→身體。畫框與鏡頭使用同一目標。
- 點選空白處留下固定藍色正方形，只進行一次對焦。新主體出現不會自動把它改成追焦。
- 主體短暫遮擋先保持距離；超過寬限不跳鎖旁人，清除藍框並回到白框待選與基本自動對焦。右側 × 可解除觸控指定。
- 主畫面各設定可點選。Q 保留取景，二級選單依手冊採橫列、直列或白平衡圖示盤。
- MENU 使用圖示分頁與雙欄設定。C1–C3 在「自訂／我的選單」載入與儲存。
- MF：選單調焦，取景放大按鈕提供 3× 顯示及邊緣輔助。MF 不顯示自動追焦框。
- 拍攝成功只讓取景區四邊亮白框約 120ms 後淡出，不疊加照片、不主動停住預覽。照片先存 App，再寫入相簿；回放可翻頁、放大、分享處理後照片／RAW、確認後刪除 App 內副本。

### 0.3 歷史缺口（0.7 狀態以上方為準）

鳥眼／鳥頭研究權重已取得，已完成受限載入、FLOAT32 Core ML 轉換與合成輸入一致性驗證；真實鳥眼準確度、App 整合與手機效能尚未驗收。本次依使用者選擇，IPA 暫不含鳥眼模型。目前鳥類只有身體偵測，**不代表鳥眼需求已完成**。模型候選、授權與部署缺口見 [研究筆記](docs/research/bird-eye-feasibility.md)。人物支援臉／眼；狗貓頭部區域來自可靠觀測關鍵點的包圍範圍，並非專用頭部偵測模型。

UI 使用程式繪製，圖示未能從手冊建立完整定義的部分使用明確文字，不使用生成圖的畸形動物圖案。AF 區域固定全畫面辨識／觸控指定；測光採系統控制，沒有假的 Canon 測光模式切換。轉盤等效焦段由實際視角推估，前置 ≈ 記號，不寫死成示意圖數值。

## 能力與誠實顯示

- P／自動：系統 AE；Tv：固定快門、ISO 回授調整；M：固定快門與 ISO；
  Fv：快門與 ISO 可各自設為自動。鏡頭限制會夾住要求值，拍攝畫面顯示實際值。
- iPhone 17 沒有可變光圈；Av 顯示為不可調，第一版不模擬光圈或景深。
- RAW 僅在目前鏡頭配置實際支援時可選；不承諾標準版 ProRAW。
- 藍框表示觸控指定位置或追蹤目標，不保證已量測眼部銳利度。白框不控制對焦座標，待選時仍使用基本自動對焦。
- 主體身分以類別與幾何位置關聯，不是人臉辨識。交叉、快速移動、長時間遮擋可能失敗。
  不會在目標遺失後聲稱已重新辨識同一個人。人物/動物識別品質取決於模型、光線與距離。
- 相片風格是獨立調校的近似效果，並非 Canon 色彩演算法；RAW 保持未套風格。
- 右側螢幕轉盤為自訂重現；沒有註冊側鍵縮放浮層。其餘介面參考手冊並固定橫向。
- 不含錄影、進階合成、包圍對焦、預拍、堆疊長曝或 Canon 配件支援。

## 開發與驗證

Windows 可修改來源；完整 Swift／iOS 編譯需由 macOS Xcode 或 GitHub Actions 執行。
在 macOS：

```sh
brew install xcodegen
python3 scripts/prepare_model.py
xcodegen generate
xcodebuild test -project R6Camera.xcodeproj -scheme R6Camera \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' CODE_SIGNING_ALLOWED=NO
```

Python 包裝測試：`python scripts/test_packaging.py`。

Swift 測試覆蓋主體鎖定不跳旁人、遮擋恢復、眼睛降級、類別篩選、
交錯歧義、待選基本 AF 與指定追焦的區別、點選空白僅一次 AF、眼頭身體降級、轉盤圓心與座標轉換及 C1–C3 保存，可在 macOS 以 `swift test` 執行。
CI 先執行核心測試、驗證裝置版 archive 與 IPA 結構，再執行模擬器介面測試。
UI 截圖另存為 `UI-screenshots` artifact；介面測試失敗時整個 run 仍會標示失敗。

真機驗收清單見 [docs/DEVICE-TESTS.md](docs/DEVICE-TESTS.md)。
建置通過不代表硬體按鍵、追焦與成像已通過真機驗證。

## 技術來源

- [Apple Camera Control](https://developer.apple.com/documentation/avfoundation/enhancing-your-app-experience-with-the-camera-control)
- [Apple 拍攝硬體按鍵](https://developer.apple.com/videos/play/wwdc2025/253/)
- [Vision 動物姿態與眼睛](https://developer.apple.com/videos/play/wwdc2023/10045/)
- [Apple 主體模型](https://developer.apple.com/machine-learning/models/)
- [手動曝光與畫質優先注意事項](https://developer.apple.com/videos/play/wwdc2026/8018/?time=827)
- [GitHub runner](https://github.com/actions/runner-images/blob/main/images/macos/xcode-27-arm64-Readme.md)

手冊 PDF 僅在本機供研究，未隨專案散布。
