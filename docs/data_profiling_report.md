# Data Profiling Report: Data Bank Project

**Author:** Nguyen Thi Bao Tran  
**Date:** 2026-08-29  
**Database:** PostgreSQL (`data_bank`)  

---

## 1. Quy mô dữ liệu & Quan sát ban đầu

### 1.1. Đánh giá quy mô dữ liệu

Bảng dưới đây tóm tắt tổng số records trong các bảng thuộc schema `data_bank`.

| Table Name | Row Count | Table Type (Inferred) | Description |
| :--- | :--- | :--- | :--- |
| `regions` | 5 | Dimension | Bảng master cho các vùng địa lý. |
| `customer_nodes` | 3,500 | Fact / Temporal | Lịch sử phân bổ customers vào các nodes. |
| `customer_transactions` | 5,868 | Fact (Event) | Các giao dịch tài chính: deposit, withdrawal, purchase. |

### 1.2. Quan sát ban đầu

Dựa trên kết quả row count, có một số quan sát quan trọng cho các bước data quality assessment và analysis tiếp theo:

- **Bảng dimension `regions`:** Có 5 records, tương ứng với 5 regions. Bảng này sẽ được dùng để join và phân tích theo địa lý.
- **Tính chất temporal của `customer_nodes`:** Bảng có 3,500 rows. Vì case study đề cập đến 500 customers, số rows lớn hơn đáng kể so với số customers. Sự hiện diện của `start_date` và `end_date` cho thấy đây là một **temporal table** hoặc dạng **Slowly Changing Dimension Type 2 (SCD Type 2)**. Bảng này theo dõi lịch sử customers được reallocated sang các nodes khác nhau theo thời gian vì mục tiêu bảo mật.
  - **Action item (đã hoàn thành):** `COUNT(DISTINCT customer_id)` = **500** ở cả `customer_nodes` lẫn `customer_transactions` — hai bảng khớp nhau, không có customer mồ côi (chi tiết: `outputs/tables/profiling/unique_customer_counts.csv`). `end_date = '9999-12-31'` được dùng để xác định node hiện tại của mỗi customer (xem §5).
- **Bảng giao dịch `customer_transactions`:** Có 5,868 transaction records. Quy mô này đủ để phân tích hành vi giao dịch, time-series và tính customer balance.
  - **Action item (đã hoàn thành):** missing values (§3), invalid transaction types (§8) và amount bất thường (§9) đã được kiểm tra đầy đủ.

---

## 2. Kiểm tra kiểu dữ liệu

### 2.1. Expected vs Actual

| Table | Column | Expected Type | Actual Type | Status |
|---|---|---|---|---|
| `regions` | region_id | INTEGER | integer | ✅ Pass |
| `regions` | region_name | VARCHAR | character varying(9) | ✅ Pass |
| `customer_nodes` | customer_id | INTEGER | integer | ✅ Pass |
| `customer_nodes` | region_id | INTEGER | integer | ✅ Pass |
| `customer_nodes` | node_id | INTEGER | integer | ✅ Pass |
| `customer_nodes` | start_date | DATE | date | ✅ Pass |
| `customer_nodes` | end_date | DATE | date | ✅ Pass |
| `customer_transactions` | customer_id | INTEGER | integer | ✅ Pass |
| `customer_transactions` | txn_date | DATE | date | ✅ Pass |
| `customer_transactions` | txn_type | VARCHAR | character varying(10) | ✅ Pass |
| `customer_transactions` | txn_amount | INTEGER | integer | ✅ Pass |

### 2.2. Quan sát

- **Tất cả columns có kiểu dữ liệu đúng như kỳ vọng.** Không cần ép kiểu dữ liệu ở bước này.
- **`txn_type`** có độ dài tối đa 10 ký tự, đủ để lưu các giá trị `deposit`, `withdrawal`, và `purchase`.
- **`region_name`** có độ dài tối đa 9 ký tự, đủ cho các giá trị như `Australia`, `America`, `Africa`, `Asia`, `Europe`.
- **Tất cả columns đều nullable (`is_nullable = YES`)**. Đây là rủi ro về mặt data quality trong production schema: các cột như `customer_id`, `region_id`, `txn_amount`, `txn_type` lý tưởng nên là `NOT NULL`. Tuy nhiên, cần xác minh thực tế bằng bước kiểm tra missing values (§3).

### 2.3. Action Items

- [x] Không cần chuyển đổi kiểu dữ liệu.
- [x] Đã kiểm tra NULL values ở các cột quan trọng (§3).

---

## 3. Phân tích Missing Values

### 3.1. NULL Value Summary

| Table | Column | Total Rows | NULL Count | Missing % | Severity |
|---|---|---:|---:|---:|---|
| `regions` | region_id | 5 | 0 | 0.00% | Low |
| `regions` | region_name | 5 | 0 | 0.00% | Low |
| `customer_nodes` | customer_id | 3,500 | 0 | 0.00% | Low |
| `customer_nodes` | region_id | 3,500 | 0 | 0.00% | Low |
| `customer_nodes` | node_id | 3,500 | 0 | 0.00% | Low |
| `customer_nodes` | start_date | 3,500 | 0 | 0.00% | Low |
| `customer_nodes` | end_date | 3,500 | 0 | 0.00% | Low |
| `customer_transactions` | customer_id | 5,868 | 0 | 0.00% | Low |
| `customer_transactions` | txn_date | 5,868 | 0 | 0.00% | Low |
| `customer_transactions` | txn_type | 5,868 | 0 | 0.00% | Low |
| `customer_transactions` | txn_amount | 5,868 | 0 | 0.00% | Low |

### 3.2. Quan sát

- **Không phát hiện NULL values ở bất kỳ bảng hoặc cột nào.** Dataset đầy đủ xét theo nghĩa NULL.
- Điều này phù hợp với đặc điểm của một synthetic dataset được tạo bằng script, thay vì dữ liệu production đi qua nhiều hệ thống ETL.
- **Lưu ý:** NULL và empty string là hai vấn đề khác nhau. Kết quả ở bước này chỉ xác nhận không có NULL. Các vấn đề như khoảng trắng thừa, chữ hoa/thường không nhất quán, hoặc empty string trong `txn_type` được kiểm tra ở §8.
- **Kết luận:** *No data cleaning was required — all records were retained.* (Không có bản ghi nào phải xóa hay impute.)

### 3.3. Decision Log

| Issue | Decision | Rationale |
|---|---|---|
| NULL values in critical columns | No action required | 0% missing rate across all columns |

### 3.4. Action Items

- [x] Không cần imputation hoặc xóa rows do missing values.
- [x] Đã kiểm tra duplicate records (§4).
- [x] Đã kiểm tra invalid/outlier values (§5, §8, §9).

---

## 4. Kiểm tra Duplicates

### 4.1. Methodology

Để đảm bảo data integrity, thực hiện 3 loại duplicate checks bằng `GROUP BY` và `HAVING COUNT(*) > 1`:

1. **Exact duplicates trong `customer_nodes`:** Kiểm tra các dòng giống hệt nhau theo 5 cột: `customer_id`, `region_id`, `node_id`, `start_date`, `end_date`.
2. **Exact duplicates trong `customer_transactions`:** Kiểm tra các dòng giống hệt nhau theo 4 cột: `customer_id`, `txn_date`, `txn_type`, `txn_amount`.
3. **Logical duplicates trong `customer_nodes`:** Kiểm tra một customer có bị gán vào nhiều nodes với cùng một `start_date` hay không.

### 4.2. Results

| Check Type | Table Name | Duplicates Found | Count | Decision |
| :--- | :--- | :---: | :---: | :--- |
| Exact Duplicate | `customer_nodes` | No | 0 | Keep |
| Exact Duplicate | `customer_transactions` | No | 0 | Keep |
| Logical Duplicate (Same start_date) | `customer_nodes` | No | 0 | Keep |

### 4.3. Quan sát

- **Data integrity cao:** Không có exact duplicates, cho thấy quá trình tạo dữ liệu không bị double-insert.
- **Temporal logic sạch:** Mỗi customer có một `start_date` duy nhất cho từng allocation event. Điều này giúp tính duration của một allocation mà không cần deduplicate trước.
- **Transaction records không bị lặp:** Không có giao dịch trùng hoàn toàn theo các cột được kiểm tra. Điều này làm giảm rủi ro tổng tiền hoặc balance bị nhân đôi do duplicate rows.

### 4.4. Action Items

- [x] Không cần duplicate removal hoặc deduplication.
- [x] Đã kiểm tra invalid values và outliers (§5, §8, §9).

---

## 5. Kiểm tra Logical Integrity & Invalid Values trong `customer_nodes`

### 5.1. Methodology

Bước này xác thực logic thời gian và tính nhất quán của bảng `customer_nodes`, vốn có dạng Slowly Changing Dimension Type 2 (SCD Type 2). Ba kiểm tra chính được thực hiện:

1. **Invalid Date Range Check:** Kiểm tra không có allocation nào có `end_date < start_date`.
2. **Active Node Count Check:** Xác nhận số active allocations (`end_date = '9999-12-31'`) khớp với tổng số unique customers.
3. **Multiple Active Nodes Check:** Đảm bảo không customer nào được gán vào nhiều active nodes cùng lúc.

### 5.2. Results Summary

| Check | Description | Expected | Actual | Status |
|---|---|---|---|---|
| Invalid Date Range | `end_date < start_date` | 0 | 0 | ✅ Pass |
| Active Node Count | `end_date = '9999-12-31'` | 500 | 500 | ✅ Pass |
| Multiple Active Nodes | `COUNT(*) > 1` per customer | 0 | 0 | ✅ Pass |

### 5.3. Quan sát

- **Temporal logic hợp lệ:** Không có records nào có `end_date` trước `start_date`.
- **100% customer coverage:** Số active node allocations là 500, khớp với số unique customers. Điều này cho thấy mỗi customer hiện đều có một node đang active.
- **Không có rủi ro double-counting:** Không customer nào có nhiều hơn một active node. Vì vậy, filter `end_date = '9999-12-31'` an toàn để xác định current node của mỗi customer — an toàn **vì §5.2 đã chứng minh mỗi customer có đúng một active allocation**, không phải vì dữ liệu "tự đẹp".
- **Sentinel value nhất quán:** Giá trị `'9999-12-31'` được dùng thống nhất để biểu thị records đang active/current.

### 5.4. Decision Log

| Issue | Decision | Rationale |
|---|---|---|
| Invalid date ranges | No action needed | 0 invalid records found |
| Active node count mismatch | No action needed | Count matches unique customers |
| Multiple active nodes per customer | No action needed | 0 anomalies detected |
| Sentinel `9999-12-31` | Keep | Đây là cờ current/active allocation, không phải lỗi dữ liệu |

### 5.5. Action Items

- [x] Không cần làm sạch (no cleaning required) hoặc imputation cho `customer_nodes`.
- [x] Xác nhận an toàn khi dùng `end_date = '9999-12-31'` để xác định current active node.
- [x] Đã kiểm tra invalid values trong `customer_transactions` (§8, §9).

---

## 6. Kiểm tra Temporal Overlap

### 6.1. Methodology

Dùng window function `LAG()` để so sánh `start_date` của allocation hiện tại với `end_date` của allocation trước đó trong cùng một customer. Nếu `start_date < previous_end_date`, điều này cho thấy các allocation periods bị overlap.

### 6.2. Results

| Check Type | Overlap Count | Decision |
|---|---:|---|
| Temporal overlap in `customer_nodes` | 0 | No action required |

### 6.3. Quan sát

- **Không phát hiện overlap**, xác nhận rằng lịch sử node allocation của từng customer diễn ra tuần tự, không có xung đột thời gian.
- Kết quả này củng cố rằng SCD Type 2 logic trong bảng `customer_nodes` được tạo nhất quán.

### 6.4. Action Items

- [x] Không cần làm sạch cho temporal overlaps.
- [x] Đã kiểm tra referential integrity (§7).

---

## 7. Kiểm tra Referential Integrity

### 7.1. Methodology

Thực hiện `LEFT JOIN` giữa các bảng để phát hiện orphan records — tức records ở một bảng không có bản ghi tương ứng ở bảng khác. Mục tiêu là đảm bảo các quan hệ khóa ngoại logic giữa các bảng đều hợp lệ.

### 7.2. Results

| Check Type | Count | Decision |
|---|---:|---|
| Customers with transactions but no node | 0 | No action needed |
| Customers with node but no transactions | 0 | No action needed |
| Nodes with invalid region_id | 0 | No action needed |

### 7.3. Quan sát

- **Referential integrity hoàn hảo:** Tất cả 500 customers xuất hiện trong cả `customer_nodes` và `customer_transactions`.
- **Region mapping hợp lệ:** Mọi `region_id` trong `customer_nodes` đều map được sang bảng `regions`.
- **Business implication:** Có thể join giữa cả ba bảng mà không lo mất dữ liệu hoặc phát sinh unmatched records.

### 7.4. Action Items

- [x] Không cần làm sạch cho referential integrity.
- [x] Đã kiểm tra `txn_type` (§8).

---

## 8. Kiểm tra Transaction Type

### 8.1. Methodology

Kiểm tra toàn bộ distinct values trong cột `txn_type` bằng `GROUP BY`, đồng thời dùng `LOWER(TRIM())` để phát hiện lỗi khoảng trắng thừa hoặc chữ hoa/thường không nhất quán.

Expected values:

```text
deposit, withdrawal, purchase