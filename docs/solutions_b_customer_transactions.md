# Section B — Customer Transactions

**Author:** Nguyen Thi Bao Tran  
**Last revised:** 2026-08-26  
**Source SQL:** `sql/04_analysis_b_customer_transactions.sql`

## Overview
Phần này giải mã hành vi giao dịch của khách hàng để trả lời câu hỏi cốt lõi: *Khách hàng đang dùng Data Bank như một "ví tiêu tiền" hay một "tài khoản tiết kiệm"?*. Câu trả lời quyết định trực tiếp đến biến số trung tâm của case study — **Closing Balance** (Số dư cuối tháng) — vì trong mô hình của Data Bank, dung lượng Data Storage cấp phát cho mỗi khách hàng tỷ lệ thuận với số tiền họ đang giữ trong tài khoản.

**Quy tắc áp dụng từ Data Profiling Report:**
- [P-8] `txn_type` hợp lệ (deposit / withdrawal / purchase) — dữ liệu sạch, không cần làm lại.
- [P-9] 1 giao dịch deposit $0 được giữ lại (keep & flag) — không ảnh hưởng đến các metric tổng tiền.
- [P-10] April 2020 bị cắt cụt (dừng ở 28/04) → Các metric đo "lưu lượng trong tháng" (flow) của April không được dùng để so sánh xu hướng với các tháng trước.

---

## Executive Summary 
1. **Data Bank đang là "Spending Wallet" chứ không phải "Savings Account":** Dù 100% khách hàng có nạp tiền, ~90% dùng tiền đó để mua sắm/rút tiền mặt ngay. Dòng tiền ròng của toàn hệ thống đang **âm $240,372**.
2. **Báo động rủi ro thấu chi (Overdraft Risk):** Số dư trung bình "bốc hơi" từ +$252 (tháng 1) xuống -$481 (tháng 4). Đến tháng 4, **56.8% khách hàng đang âm tiền**.
3. **Nghịch lý Engagement:** Khách hàng giao dịch ngày càng nhiều (engagement tăng), nhưng sức khỏe tài khoản lại ngày càng tệ. Chỉ **37% khách hàng** thực sự nuôi lớn được tài khoản của mình.
4. **Hệ quả cho Section C:** Không được dùng mức tăng trưởng trung bình để dự báo Data Storage. Phải dùng số dư thực tế và chốt quy tắc "sàn" (floor) cho các tài khoản đang âm tiền.

---

## B.1. Cơ cấu giao dịch và dòng tiền ròng
*(What is the unique count and total amount for each transaction type?)*

### Business Context
Hiểu được tiền chảy vào và chảy ra khỏi hệ thống qua những kênh nào là bước đầu tiên để mô hình hóa dung lượng Data Storage (tiền vào = data phình ra, tiền ra = data co lại).

### Insight: Platform là hệ sinh thái chi tiêu, không phải két tiết kiệm
- **Đa số khách hàng dùng Data Bank để tiêu tiền:** Dù 100% khách hàng (500/500) có nạp tiền, có tới ~90% khách hàng phát sinh giao dịch `purchase` hoặc `withdrawal`. Tiền vừa nạp vào đã nhanh chóng được đẩy ra khỏi hệ thống.
- **Dòng tiền ròng của hệ thống đang âm (-$240,372):** Tổng tiền khách hàng rút ra/mua sắm ($1,599,540) lớn hơn số tiền họ nạp vào ($1,359,168). Đây là "tín hiệu báo trước" (leading indicator) cho thấy số dư tài khoản của toàn hệ thống sẽ đi xuống — một giả thuyết sẽ được chứng minh rõ ràng ở câu B.4.
- **Dấu vết dữ liệu giả lập (Synthetic Data):** Giá trị trung bình của mọi loại giao dịch đều xấp xỉ $500, phản ánh phân phối đều (uniform), khác với dữ liệu ngân hàng thực tế (thường lệch phải với vô số giao dịch nhỏ vài đô la và một vài giao dịch lớn).

### Result
| txn_type | txn_count | unique_customer_count | total_amount |
|---|---:|---:|---:|
| deposit | 2,671 | 500 | $1,359,168 |
| purchase | 1,617 | 448 | $806,537 |
| withdrawal | 1,580 | 439 | $793,003 |

---

## B.2. Hành vi nạp tiền điển hình
*(What is the average total historical deposit counts and amounts for all customers?)*

### Business Context
Xác định "nhịp đập" nạp tiền của khách hàng để làm baseline ước lượng dung lượng storage trung bình mà mỗi khách hàng chiếm dụng.

### Insight: Nhịp độ nạp tiền bám sát chu kỳ nhận lương
- **Tần suất nạp:** Trung bình mỗi khách hàng nạp **~5.34 lần trong 4 tháng**
(~1.3 lần/tháng). Nhịp này gần nhất với **một khoản nạp chính theo tháng
(monthly) kèm vài khoản phát sinh** — nếu khách nhận lương weekly/bi-weekly
thật, ta phải quan sát ~17 / ~8–9 lần nạp trong kỳ. Lưu ý: với dữ liệu
synthetic, đây là giả thuyết hành vi, không phải kết luận về chu kỳ lương.
- **Baseline Storage:** Mỗi khách hàng mang lại trung bình **$2,718** tiền gửi trong toàn kỳ. Con số này là input nền tảng để ước lượng dung lượng data storage trung bình khi giải bài toán cấp phát data ở Section C.

### Result
| avg_deposit_count_per_customer | avg_deposit_amount_per_customer |
|---:|---:|
| 5.34 | $2,718.34 |

---

## B.3. Nhóm khách hàng "Active khỏe mạnh" theo tháng
*(For each month - how many Data Bank customers make more than 1 deposit and either 1 purchase or 1 withdrawal in a single month?)*

### Business Context
Đo lường **Engagement thực sự**. Một khách hàng được coi là "active khỏe mạnh" khi họ vừa duy trì nạp tiền (>1 lần), vừa sử dụng tiện ích chi tiêu/rút tiền ngay trong tháng đó.

### Insight: Engagement tăng trưởng, nhưng là engagement của "Net-spenders"
- **Tăng trưởng đều ở các tháng trọn vẹn:** Tỷ lệ khách hàng "active khỏe mạnh" tăng từ **33.6% (tháng 1) lên 38.4% (tháng 3)**. Platform đang giữ chân và kích thích người dùng hoạt động mạnh mẽ hơn qua từng tháng.
- **Tháng 4 không phải là sự sụt giảm:** Con số 70 khách hàng (14%) chỉ phản ánh việc dữ liệu bị cắt cụt ở ngày 28/04 (Quy tắc P-10), chưa đủ thời gian để tích lũy hành vi, tuyệt đối không được kết luận là "người dùng rời bỏ nền tảng".

### Result
| txn_month | qualifying_customers | % of customer base |
|---|---:|---:|
| 2020-01 | 168 | 33.6% |
| 2020-02 | 181 | 36.2% |
| 2020-03 | 192 | 38.4% |
| 2020-04 | 70 | *(Tháng cắt cụt)* |

---

## B.4. Sức khỏe tài khoản (Closing Balance) - Biến số trung tâm
*(What is the closing balance for each customer at the end of the month?)*

### 🎯 Business Context
Closing Balance (Số dư cuối tháng) là **trái tim của bài toán Data Allocation**. Data Bank cần biết chính xác tại thời điểm cuối tháng, trong tài khoản của khách hàng còn bao nhiêu tiền để cấp phát dung lượng server lưu trữ tương ứng.

### 💡 Insight: Báo động rủi ro thấu chi (Overdraft Risk)
- **Sức khỏe tài khoản suy giảm nghiêm trọng:** Số dư trung bình của hệ thống "bốc hơi" từ **+$252 (tháng 1) xuống -$481 (tháng 4)**. 
- **Hơn một nửa customer base đang "thấu chi":** Số lượng khách hàng âm tiền tăng từ 157 người (31.4%) lên **284 người (56.8%)** vào tháng 4. Nếu đây là ngân hàng thực tế, bộ phận Quản trị Rủi ro (Risk Management) đã phải kích hoạt báo động đỏ và siết chặt hạn mức rút tiền.
- **Sự phân hóa giàu nghèo nới rộng:** Khoảng cách giữa người có số dư cao nhất và thấp nhất giãn ra liên tục (từ $7,180 ở tháng 1 lên $13,291 ở tháng 4). Một nhóm nhỏ đang tích lũy rất tốt, trong khi một nhóm lớn rơi tự do vào trạng thái nợ.
- **Cross-check xác thực tính toàn vẹn của Pipeline:** Tổng số dư âm của toàn hệ thống cuối tháng 4 = −480.74 × 500 - **-$240,370** khớp gần như tuyệt đối với dòng tiền ròng âm ở câu B.1 (-$240,372, lệch $2 do làm tròn).  Vì closing balance chính là tích lũy của mọi giao dịch, hai cách tính độc lập bắt buộc phải khớp nhau — và chúng khớp: logic carry-forward (tháng không giao dịch giữ nguyên số dư) hoạt động đúng.

### 📊 Result (Summary theo tháng)
| txn_month | avg_closing_balance | min | max | customers_negative_balance |
|---|---:|---:|---:|---:|
| 2020-01 | $252.18 | -$3,912 | $3,268 | 157 (31.4%) |
| 2020-02 | -$27.42 | -$4,646 | $3,641 | 237 (47.4%) |
| 2020-03 | -$369.18 | -$7,953 | $4,183 | 271 (54.2%) |
| 2020-04 | -$480.74 | -$7,953 | $5,338 | 284 (56.8%) |

### 📈 Visualization

![Monthly closing balance trend vs negative-balance customers](../outputs/charts/monthly_balance_trend.png)

*Avg closing balance rơi từ +$252 xuống −$481 đúng lúc số customers âm balance tăng 157 → 284 (31.4% → 56.8%). Hai đường ngược chiều này là bằng chứng trực quan cho "overdraft risk escalation".*
---

## B.5. Tỷ lệ khách hàng thực sự "tích lũy tài sản"
*(What is the percentage of customers who increase their closing balance by more than 5%?)*

### 🎯 Business Context
Đo lường sức khỏe tăng trưởng. Bao nhiêu phần trăm khách hàng thực sự "nuôi lớn" được tài khoản của mình (>5% so với tháng trước)? Nhóm này chính là động lực làm tăng nhu cầu Data Storage của hệ thống.

### 💡 Insight: Nghịch lý Engagement vs Balance Health
- **Đa số khách hàng đang "đốt" tiền:** Chỉ có **37% khách hàng (185/500)** có ít nhất một tháng gia tăng số dư >5%. 63% còn lại giữ nguyên, hoặc để tài khoản "chảy máu".
- **Nghịch lý thú vị:** Ghép B.3 và B.5 ta thấy: Khách hàng giao dịch ngày càng nhiều (B.3 tăng), nhưng sức khỏe tài khoản lại ngày càng tệ (B.5 giảm dần: 127 người ở T2 → 85 người ở T3 → 48 người ở T4). 
- **Kết luận Strategic:** Data Bank đang sở hữu một tệp khách hàng **"Net-spenders"** (người chi tiêu ròng). Họ dùng app rất nhiều, nhưng là để tiêu tiền của chính họ hoặc (vay thấu chi) hệ thống.

### 📊 Result
| pct_customers_increased_over_5pct |
|---:|
| **37.00%** |

*(Breakdown theo tháng: T2 = 127 khách | T3 = 85 khách | T4 = 48 khách)*

---

## 🎯 Tổng kết Section B
1. **Bản chất khách hàng:** Data Bank đang vận hành như một **Spending Wallet**. Engagement rất cao nhưng là engagement của nhóm Net-spenders, dẫn đến dòng tiền ròng của hệ thống bị âm.
2. **Rủi ro vận hành:** Hơn 50% khách hàng đang âm tiền vào cuối kỳ quan sát. Mọi mô hình cấp phát Data Storage ở Section C **bắt buộc** phải trả lời câu hỏi: *"Data Bank có cấp phát dung lượng lưu trữ (allocation) cho một tài khoản đang âm tiền hay không?"*.
3. **Chiến lược dự báo Storage:** Không được dùng mức tăng trưởng trung bình (vì base đang co lại). Phải sử dụng chính xác **Closing Balance thực tế của từng tháng (B.4)** làm input đầu vào cho các mô hình giả lập (Option 1, 2, 3) ở Section C.