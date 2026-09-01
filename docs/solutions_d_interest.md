# Section D — Extra Challenge: Interest-based Data Growth

**Author:** Nguyen Thi Bao Tran
**Last revised:** 2026-08-29
**Source SQL:** `sql/06_analysis_d_interest.sql`

## Overview

Section D thử nghiệm cơ chế cấp phát data thứ tư: **khách hàng được "thưởng" thêm dung lượng lưu trữ dựa trên lãi suất tính theo ngày** — giống tài khoản tiết kiệm truyền thống. Lãi suất năm 6%, tính cuối mỗi ngày, cộng vào data allocation.

Hai biến thể được mô phỏng:
- **D.1 — Simple interest (yêu cầu chính của đề):** lãi tính trên số dư thực tế mỗi ngày, KHÔNG nhập gốc.
- **D.2 — Daily compounding (bonus "stamina"):** lãi nhập gốc hằng ngày, ngày hôm sau tính lãi trên cả gốc lẫn lãi.

**Quy tắc & giả định:**
- [D-RATE] Daily rate = 6%/365 (ước lệ ngân hàng chuẩn; 2020 là năm nhuận 366 ngày — lựa chọn 365 được tài liệu hóa).
- [D-FLOOR] Chỉ số dư **dương** mới sinh lãi (không trả lãi trên overdraft) — nhất quán với [C-NEG]; allocation floor tại 0.
- [D-SNAP] Provisioning tháng = allocation tại thời điểm cuối tháng (cùng convention snapshot với C.4).
- [P-10] April cắt cụt ở 28/04 → lãi tháng 4 chỉ phủ 28 ngày.

---

## Executive Summary (Dành cho Business & IT Stakeholder)

1. **Lãi suất là "gia vị", không phải "nguyên liệu":** tổng lãi 4 tháng ≈ **4,496 data units**, chỉ ~**1.7%** trên nền ~265,000 units cấp phát theo số dư. Nhu cầu storage do lãi tạo ra là nhỏ và dự báo được — IT không cần lo quá tải vì cơ chế này.
2. **Option lãi là đường cong mượt nhất trong cả 4 options:** tăng đều 236k → 269k qua 4 tháng, không có biến động như Option 3 → dễ hoạch định capacity nhất.
3. **Nghịch lý compounding:** trong tệp khách hàng **net-spender** này, **lãi kép cho ÍT data hơn lãi đơn** (268,469 vs 269,353 ở tháng 4). Lý do: withdrawal "ăn" cả phần lãi đã nhập gốc trong mô hình kép, trong khi mô hình đơn giữ lãi trong một bucket riêng không bị rút mất. Đây là phát hiện quan trọng cho thiết kế sản phẩm.
4. **Cơ hội sản phẩm:** cơ chế "giữ tiền = được thêm data" là đòn bẩy hành vi có thể đảo ngược xu hướng net-spender đã phát hiện ở Section B — biến khách tiêu tiền thành khách tích lũy, tăng storage stickiness.

---

## D.1. Simple Interest — Data required theo tháng
*(How much data would be required for this option on a monthly basis?)*

### 🎯 Business Context
Data Bank muốn "thưởng" khách hàng bằng dung lượng lưu trữ tăng thêm dựa trên tiền họ giữ trong tài khoản, như một chương trình khách hàng thân thiết. Câu hỏi cho IT: mỗi tháng cần provision thêm bao nhiêu?

### 🧠 Approach
- Mỗi ngày, lãi = `GREATEST(balance cuối ngày, 0) × 0.06 / 365` (chỉ số dư dương sinh lãi).
- **Simple interest:** lãi KHÔNG nhập gốc — cộng dồn vào một bucket riêng, ngày nào cũng tính trên số dư thực tế (không tính trên lãi tích lũy).
- Allocation cuối tháng M = `GREATEST(closing_M, 0) + Σ lãi lũy kế từ 01/01 đến cuối tháng M`.

### 📊 Result

| Tháng | Total data required |
|---|---:|
| 2020-01 | 236,276.51 |
| 2020-02 | 263,436.93 |
| 2020-03 | 264,265.67 |
| 2020-04 | 269,352.80 |

*(Output: `outputs/tables/d1_simple_interest_monthly.csv`)*

### 💡 Insight
- **Tăng trưởng chậm, đều và dự báo được:** 236k → 269k sau 4 tháng. Không có tháng nào nhảy vọt hay rơi tự do — đây là đường cong provisioning "hiền" nhất trong cả 4 options đã khảo sát.
- **Phần lãi chỉ là lớp mỏng trên nền số dư:** tháng 4, tổng lãi lũy kế ≈ 4,496 units trên nền ~264,857 units số dư dương → **lãi đóng góp ~1.7%**. Thông điệp cho IT: cơ chế thưởng này gần như không tạo áp lực hạ tầng.

### 🔍 Sanity Check
- Tháng 1: 236,276.51 − 681.51 (lãi tháng 1) = **235,595** = đúng bằng tổng `GREATEST(Jan closing, 0)` ở C.4 (chính là `opt1_floored` tháng 2) ✓ — ba query độc lập ở hai section khớp nhau.
- Tháng 4: 269,352.80 − 4,495.79 (tổng lãi toàn kỳ) = **264,857** = tổng số dư dương cuối tháng 4 ✓.

---

## D.1b. Lãi phát sinh theo tháng (bảng hỗ trợ)

| Tháng | Interest earned trong tháng | Số ngày | Lãi bình quân/ngày |
|---|---:|---:|---:|
| 2020-01 | 681.51 | 31 | 21.98 |
| 2020-02 | 1,247.41 | 29 | 43.01 |
| 2020-03 | 1,365.74 | 31 | 44.06 |
| 2020-04 | 1,201.13 | 28 | 42.90 |

*(Output: `outputs/tables/d1b_interest_by_month.csv`)*

### 💡 Insight
- **Lãi/ngày ổn định ở mức ~43–44 units từ tháng 2 trở đi** → "cỗ máy lãi" chạy đều, phản ánh nền số dư dương ổn định ~260k units của hệ thống.
- **Tháng 1 chỉ ~22 units/ngày (một nửa):** khách hàng khởi động từ 0 và nạp tiền rải rác trong tháng, nên nền số dư dương trung bình của tháng 1 thấp hơn hẳn. Đây là hiệu ứng ramp-up, không phải bất thường.
- Tháng 4 thấp hơn tháng 3 (1,201 vs 1,366) **chỉ vì ít ngày hơn** (28 vs 31): lãi/ngày gần như bằng nhau (42.90 vs 44.06) — nhất quán với caveat P-10, không phải khách hàng ngừng tích lũy.

---

## D.2. Daily Compounding Interest — Bonus Challenge

### 🎯 Business Context
Đội Data Bank gợi ý thêm: nếu lãi **nhập gốc hằng ngày** (lãi mẹ đẻ lãi con), nhu cầu data sẽ khác đi thế nào?

### 🧠 Approach
- Mô hình **đệ quy theo ngày** (recursive CTE): `V_t = (V_{t-1} + net_t) × (1 + 0.06/365)` nếu kết quả dương; nếu âm thì giữ nguyên (không lãi trên nợ).
- Khác biệt bản chất với D.1: **lãi hòa vào gốc** và chịu chung số phận với gốc — các withdrawal sau đó có thể "cuốn trôi" cả phần lãi đã nhập.
- Allocation cuối tháng = `GREATEST(compounded balance, 0)`, tổng theo toàn bộ customers.

### 📊 Result

| Tháng | Total data required |
|---|---:|
| 2020-01 | 236,185.32 |
| 2020-02 | 263,094.77 |
| 2020-03 | 263,549.35 |
| 2020-04 | 268,469.18 |

*(Output: `outputs/tables/d2_compound_interest_monthly.csv`)*

---

## D.1 vs D.2 — Nghịch lý Compounding (phát hiện đáng giá nhất Section D)

| Tháng | D.1 Simple | D.2 Compound | Chênh lệch (D.1 − D.2) |
|---|---:|---:|---:|
| 2020-01 | 236,276.51 | 236,185.32 | +91.19 |
| 2020-02 | 263,436.93 | 263,094.77 | +342.16 |
| 2020-03 | 264,265.67 | 263,549.35 | +716.32 |
| 2020-04 | 269,352.80 | 268,469.18 | +883.62 |

### 💡 Insight: Lãi kép lại cho ÍT data hơn lãi đơn — vì sao?

Trực giác thông thường nói "lãi kép luôn ≥ lãi đơn". Nhưng dữ liệu cho điều ngược lại, và nguyên nhân nằm ở **hành vi khách hàng**, không phải toán học:

1. **D.1 — lãi được "khóa" trong bucket riêng:** bucket lãi lũy kế chỉ có tăng, không bao giờ bị withdrawal rút mất. Khách tiêu sạch tiền vẫn giữ trọn phần lãi đã kiếm.
2. **D.2 — lãi hòa vào gốc và "trần trụi" trước withdrawal:** mỗi lần khách rút tiền, tiền rút **ăn cả vào phần lãi đã nhập gốc**. Với tệp khách hàng mà 74.6% từng âm tiền và hệ thống net outflow −$240,372 (Section B), dòng withdrawal liên tục "xói mòn" chính phần lãi kép.
3. **Khoảng cách giãn rộng theo thời gian** (+91 → +884): lãi tích lũy càng nhiều thì phần "có thể bị ăn mất" trong mô hình kép càng lớn.

→ **Kết luận sản phẩm:** trong một hệ sinh thái net-spender, **simple interest với sổ lãi riêng là cơ chế hào phóng hơn cho khách hàng**, còn compounding là cơ chế "actuarially fair" hơn cho ngân hàng. Chọn thiết kế nào là quyết định chiến lược, không phải kỹ thuật.

---

## 🎯 Recommendation cho Data Bank

1. **Triển khai interest như một lớp thưởng bổ sung, không thay thế Option 1/3:** uplift ~1.7% là chi phí hạ tầng không đáng kể, nhưng giá trị cảm nhận với khách hàng ("giữ tiền = được thêm data") rất cao.
2. **Chọn sổ lãi simple (khóa lãi) nếu mục tiêu là growth/retention** — đúng định hướng "grow the customer base" của ban quản trị. Compounding chỉ nên dùng nếu cần kiểm soát chi phí thưởng.
3. **Provisioning:** baseline ~265k units + dự phòng tăng ~1–2k units/tháng do lãi; budget tháng gần nhất ≈ **270k units**.
4. **Cơ hội chiến lược:** dùng cơ chế thưởng lãi như đòn bẩy hành vi để **đảo ngược xu hướng net-spender** (Section B) — khách giữ tiền lâu hơn để nhận thêm data → balance health cải thiện → nhu cầu storage bền vững hơn.

---

## 🏁 Tổng kết toàn bộ Case Study (A → B → C → D)

**Một câu chuyện duy nhất xuyên suốt 4 sections:**

| Section | Câu hỏi lớn | Câu trả lời |
|---|---|---|
| **A** | Hạ tầng trông thế nào? | 25 nodes phân tán đều, reallocation ~14.6 ngày nhất quán mọi region — nền móng ổn định. |
| **B** | Khách hàng cư xử thế nào? | **Spending wallet:** vào nhanh ra nhanh, net flow −$240k, 56.8% âm balance cuối kỳ — sức khỏe tài khoản suy giảm. |
| **C** | Cần bao nhiêu data, cấp phát theo cách nào? | Bắt buộc zero-floor; mô hình lag (Opt 1/2) gãy với net-spenders; **Option 3 real-time** khớp cam kết thương hiệu dù tốn hơn. |
| **D** | Lãi suất thay đổi cuộc chơi không? | Không về lượng (+1.7%) nhưng **có về chất**: thiết kế sổ lãi quyết định khách hàng được thưởng bao nhiêu; compounding paradox cho thấy hành vi khách hàng bẻ cong cả toán học lãi suất. |

**Thông điệp cuối cho ban quản trị Data Bank:** lợi thế cạnh tranh "real-time distributed security" chỉ bền khi hạ tầng cấp phát data **co giãn theo thời gian thực (Option 3)**, có **sàn zero-floor**, và dùng **lãi suất như đòn bẩy hành vi** để chuyển khách hàng từ tiêu tiền sang tích lũy.