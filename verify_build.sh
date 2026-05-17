#!/bin/bash

# 定義專案路徑與檔案
PROJECT_PATH="/Users/sufuhan/Documents/SuPOS_iPad"
PROJECT_FILE="SuPOS_iPad.xcodeproj"
SCHEME="SuPOS_iPad"

echo "⏳ SuPOS 編譯驗證中，請稍候..."

# 執行編譯，並將所有輸出存入變數中
BUILD_OUTPUT=$(xcodebuild -project "$PROJECT_PATH/$PROJECT_FILE" \
    -scheme "$SCHEME" \
    -destination 'generic/platform=iOS Simulator' \
    build CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO 2>&1)

# 檢查 xcodebuild 的結束狀態碼 (0 代表成功)
if [ $? -eq 0 ]; then
    echo "✅ [SUCCESS] 編譯綠燈！沒有發現語法或型別錯誤。"
    exit 0
else
    echo "❌ [FAILED] 編譯紅燈！抓取到以下錯誤訊息："
    echo "--------------------------------------------------"
    
    # 利用 grep 抓取包含 "error:" 的行，並印出錯誤的上下 2 行以提供上下文
    echo "$BUILD_OUTPUT" | grep -i "error:" -B 1 -A 2
    
    echo "--------------------------------------------------"
    echo "💡 請將上述錯誤丟給 AI 進行修正。"
    exit 1
fi
