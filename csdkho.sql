-- CSDL Quản lý kho hàng thanh lý LK
-- Bản cập nhật: bảng khach_hang (mã KH, tên KH, SĐT, địa chỉ) - đơn giản, không tag/không phân loại
-- Bỏ cột nguon_don, bổ sung trigger + stored procedure

/* ========================================================================
   GHI CHÚ: CÁC THAY ĐỔI SO VỚI BẢN GỐC (Sql.sql)
   ========================================================================
   [1] Dòng ~287, bảng chi_tiet_phieu_nhap_kho:
       - Lỗi: cột "thanh_tien AS (...) PERSISTED;" kết thúc bằng dấu ";"
         thay vì dấu ",". Trong CREATE TABLE, các cột phải cách nhau
         bằng dấu phẩy -> lỗi này làm cả script KHÔNG CHẠY ĐƯỢC từ đây trở đi.
       - Sửa: đổi ";" thành ",".

   [2] Trigger trg_donhang_capnhat_thanhtien, trg_sku_ngaycapnhat,
       trg_donhang_hoan_ton_khi_huy, trg_kiemke_capnhat_ton:
       - Lỗi: dùng "TRIGGER_NESTLEVEL() > 1 RETURN" (không tham số) để
         chống đệ quy. Hàm này đếm TẤT CẢ trigger đang lồng nhau trong
         toàn hệ thống, không riêng trigger hiện tại.
         Hậu quả cụ thể: khi bán hàng, chi_tiet_don_hang insert ->
         trg_cthd_tru_ton_khi_ban chạy -> update san_pham_sku -> gọi
         trg_sku_ngaycapnhat. Lúc này mức lồng đã = 2 (dù là lần đầu
         trigger này chạy) nên nó tự RETURN, bỏ qua việc cập nhật
         ngay_cap_nhat mỗi khi bán/hủy đơn.
       - Sửa: đổi thành "TRIGGER_NESTLEVEL(OBJECT_ID('tên_trigger')) > 1
         RETURN" - chỉ đếm số lần CHÍNH trigger đó bị gọi lồng (tự đệ quy
         thật sự), không bị ảnh hưởng bởi trigger của bảng khác.

   [3] Trigger trg_cthd_tru_ton_khi_ban:
       - Lỗi: khi hết hàng, trigger gọi "ROLLBACK TRANSACTION" trực tiếp.
         Việc này đóng transaction đột ngột ngay trong trigger, khiến
         khối TRY/CATCH của sp_TaoDonHang (nơi gọi INSERT dẫn tới trigger
         này) không nhận lỗi theo đúng luồng mong đợi, dễ phát sinh thêm
         lỗi 266 "transaction count mismatching".
       - Sửa: bỏ ROLLBACK TRANSACTION thủ công, chỉ giữ RAISERROR + RETURN,
         và thêm "SET XACT_ABORT ON" ngay đầu trigger để đảm bảo transaction
         tự động bị đánh dấu rollback, lỗi được ném đúng lên khối CATCH
         của thủ tục gọi.

   [4] Trigger trg_cthd_tru_ton_khi_ban:
       - Lỗi: kiểm tra và trừ tồn kho join trực tiếp với "inserted" theo
         ma_sku. Nếu 1 đơn hàng có 2 dòng chi tiết cùng trỏ tới 1 SKU,
         "UPDATE ... FROM" không tự cộng dồn theo các dòng trùng khớp,
         mà chỉ áp dụng 1 dòng bất kỳ -> trừ tồn kho sai/thiếu.
       - Sửa: gộp SUM(so_luong) theo ma_sku (subquery GROUP BY) trước khi
         kiểm tra đủ tồn và trước khi UPDATE trừ kho.

   ------------------------------------------------------------------------
   BỔ SUNG MỚI (khuyến mãi + hoàn tất nhập kho)
   ------------------------------------------------------------------------
   GHI CHÚ: Phân quyền theo vai_tro KHÔNG được enforce ở tầng CSDL trong
   bản này (đã bỏ bảng phan_quyen_chuc_nang, SP sp_KiemTraQuyen và các
   tham số @ma_nguoi_thuc_hien) — theo lựa chọn xử lý phân quyền ở tầng
   web (ASP.NET MVC: Controller filter + ẩn/hiện layout theo Session
   VaiTro), vì chỉ có 1 ứng dụng truy cập CSDL nên không cần enforce
   thêm ở DB, tránh phải bảo trì phân quyền ở 2 nơi.

   [5] TRG mới trg_donhang_kiemtra_khuyenmai (ON don_hang, AFTER INSERT,
       UPDATE): chặn nếu ma_khuyen_mai được gán nhưng khuyến mãi đã hết
       hạn / chưa active / đơn chưa đạt gia_tri_don_toi_thieu. Chỉ kiểm
       tra khi cột ma_khuyen_mai thực sự thay đổi (UPDATE(ma_khuyen_mai))
       để tránh việc đơn hàng cũ bị lỗi "hết hạn" khi chỉ sửa thông tin khác.

   [6] SP mới sp_ApDungKhuyenMai: nhận ma_don_hang + mã code khuyến mãi,
       tự tính tien_giam_gia theo loai_giam_gia (PERCENT/FIXED_AMOUNT),
       không cho giảm vượt quá tong_tien_hang.

   [7] Phiếu nhập kho trước đây KHÔNG có bước nào cộng tồn kho thực tế
       khi hoàn tất — đây là lỗ hổng nghiệp vụ được bổ sung:
       - TRG mới trg_phieunhap_capnhat_tongtien (ON chi_tiet_phieu_nhap_kho):
         tự tính lại tong_tien_hang của phieu_nhap_kho mỗi khi chi tiết
         phiếu nhập thay đổi.
       - SP mới sp_HoanTatNhapKho: chuyển trạng thái phiếu nhập sang
         COMPLETED và CỘNG tồn kho theo so_luong_thuc_nhan (tương tự cách
         sp_HoanTatKiemKe / trg_kiemke_capnhat_ton xử lý cho kiểm kê).

   [8] Thêm 2 CHECK constraint còn thiếu:
       - khuyen_mai: ngay_ket_thuc > ngay_bat_dau
       - chi_tiet_kiem_ke: so_luong_thuc_te >= 0

   ------------------------------------------------------------------------
   BỔ SUNG MỚI (rà soát và thêm các ràng buộc dữ liệu còn thiếu)
   ------------------------------------------------------------------------
   [9] CHECK chặn giá trị tiền/số lượng âm ở các cột trước đây KHÔNG có
       ràng buộc gì (trước đây dễ bị ghi giá trị âm nếu tầng ứng dụng
       tính sai hoặc có ai UPDATE trực tiếp bỏ qua SP):
       - san_pham_sku: gia_von >= 0, gia_niem_yet >= 0
       - don_hang: tong_tien_hang >= 0, tien_giam_gia >= 0,
         phi_van_chuyen >= 0, thanh_tien >= 0
       - chi_tiet_don_hang: don_gia >= 0, gia_von >= 0, thanh_tien_dong >= 0
       - chi_tiet_phieu_nhap_kho: so_luong_ke_hoach >= 0,
         so_luong_thuc_nhan >= 0, don_gia_nhap >= 0
       - khuyen_mai: gia_tri_giam >= 0, gia_tri_don_toi_thieu >= 0
       - chi_tiet_kiem_ke: so_luong_he_thong >= 0 (trước đây chỉ có
         so_luong_thuc_te >= 0, thiếu vế còn lại)

   [10] CHECK logic nghiệp vụ còn thiếu:
       - khuyen_mai: nếu loai_giam_gia = 'PERCENT' thì gia_tri_giam phải
         trong khoảng 0-100. Trước đây không có gì chặn nhập vd 150%,
         dù sp_ApDungKhuyenMai có tự giới hạn số tiền giảm thực tế, nhưng
         đọc trực tiếp cột gia_tri_giam để hiển thị "% giảm" sẽ bị sai.
       - don_hang: tien_giam_gia <= tong_tien_hang. Trước đây chỉ được
         sp_ApDungKhuyenMai giới hạn, nếu UPDATE trực tiếp bỏ qua SP thì
         có thể làm giảm giá vượt tổng tiền hàng -> thanh_tien âm.

   [11] UNIQUE bổ sung:
       - san_pham_sku: mã vạch (ma_vach) phải duy nhất nếu có giá trị
         (dùng unique filtered index vì cho phép NULL). Trước đây không
         có ràng buộc, 2 SKU khác nhau có thể trùng mã vạch, khiến
         sp_QuetSkuNhapKho (tìm theo ma_vach) chọn nhầm SKU khi bị trùng.
       - san_pham_sku: (ma_lo_hang, so_thu_tu) phải là duy nhất, tránh
         trùng số thứ tự của 2 SKU trong cùng 1 lô hàng.

   GHI CHÚ: KHÔNG thêm ràng buộc "đơn COMPLETED bắt buộc phải PAID" vì
   đây là lựa chọn nghiệp vụ tùy shop (có nơi cho giao hàng COD trước,
   thu tiền sau) - cần xác nhận quy trình thực tế trước khi enforce ở
   tầng CSDL, tránh chặn nhầm luồng hợp lệ.

   ------------------------------------------------------------------------
   BỔ SUNG MỚI (chặn hủy đơn hàng sau khi đã tạo) - ĐÃ ĐƯỢC SỬA LẠI Ở MỤC [14]
   ------------------------------------------------------------------------
   [12] (ĐÃ THAY THẾ BỞI [14], xem bên dưới) Vì đây là hệ thống nội bộ quản
        lý kho (nhân viên thao tác, không phải web cho khách tự đặt hàng),
        quy tắc BAN ĐẦU là: MỘT KHI ĐƠN HÀNG ĐÃ ĐƯỢC TẠO THÌ KHÔNG ĐƯỢC PHÉP
        HỦY NỮA, bất kể đang ở trạng thái nào - thực hiện bằng trigger
        trg_donhang_chan_huy chặn tuyệt đối mọi UPDATE sang CANCELLED.
        Quy tắc này sau đó được nới lỏng lại ở mục [14] (cho phép hủy có
        điều kiện thay vì chặn hết) nên trigger trg_donhang_chan_huy đã bị
        BỎ khỏi file - chỉ giữ lại đoạn này trong changelog để biết lịch sử.

   ------------------------------------------------------------------------
   BỔ SUNG MỚI (loại bỏ trạng thái DRAFT không còn tác dụng)
   ------------------------------------------------------------------------
   [13] Bỏ trạng thái 'DRAFT' khỏi don_hang.trang_thai. Lý do: sp_TaoDonHang
        luôn tạo đơn thẳng ở CONFIRMED, DRAFT chưa từng thực sự được dùng
        trong bất kỳ luồng nào (chỉ tồn tại như giá trị mặc định của cột và
        1 điều kiện chưa từng có tác dụng trong trg_cthd_tru_ton_khi_ban).
        - don_hang.trang_thai: đổi DEFAULT từ 'DRAFT' sang 'CONFIRMED',
          bỏ 'DRAFT' khỏi CHECK constraint (chỉ còn CONFIRMED/COMPLETED/
          CANCELLED).
        - trg_cthd_tru_ton_khi_ban: sửa điều kiện kiểm tra từ
          "NOT IN ('DRAFT', 'CONFIRMED')" thành "<> 'CONFIRMED'".

   ------------------------------------------------------------------------
   BỔ SUNG MỚI (sửa lại quy tắc hủy đơn: cho phép có điều kiện thay vì
   chặn tuyệt đối như mục [12])
   ------------------------------------------------------------------------
   [14] Quy tắc mới: CHỈ "ông chủ" (vai_tro = 'CHU') mới có quyền hủy đơn
        hàng, VÀ chỉ hủy được đơn CHƯA thanh toán (UNPAID). Đơn đã PAID thì
        không ai hủy được, kể cả ông chủ.

        - Đã BỎ trigger trg_donhang_chan_huy (mục [12]) vì không còn chặn
          tuyệt đối nữa. Điều kiện "đơn đã PAID không được hủy" KHÔNG cần
          trigger riêng vì bảng don_hang đã có sẵn CONSTRAINT
          CK_donhang_huy_chuathanhtoan chặn tuyệt đối tổ hợp CANCELLED+PAID
          ở tầng bảng từ trước (không ai bypass được).
        - Điều kiện "chỉ CHU mới được hủy" KHÔNG THỂ đặt trong trigger vì
          trigger không biết ai đang thực hiện thao tác (đúng theo hướng đã
          chọn trước đây: phân quyền xử lý ở tầng ứng dụng). Vì vậy được
          kiểm tra trong sp_HuyDonHang qua tham số mới @ma_nguoi_thuc_hien -
          tầng web PHẢI truyền vào ID người đang đăng nhập (lấy từ Session),
          KHÔNG được để người dùng tự nhập giá trị này.
        - vai_tro của nguoi_dung được bổ sung thêm giá trị 'CHU' vào CHECK
          constraint (do người dùng tự thêm trong file gốc trước khi upload
          lại, không phải Claude thêm).
        - sp_HuyDonHang: viết lại để thực sự thực hiện việc hủy (trước đây
          ở mục [12] luôn báo lỗi ngay từ đầu, giờ được hoạt động trở lại
          nếu đủ điều kiện).
        - HỆ QUẢ: trigger trg_donhang_hoan_ton_khi_huy (hoàn kho khi hủy)
          hoạt động BÌNH THƯỜNG TRỞ LẠI, vì đơn chưa thanh toán giờ lại có
          thể được hủy qua sp_HuyDonHang.

   ------------------------------------------------------------------------
   BỔ SUNG MỚI (khóa quyền UPDATE trực tiếp, buộc đi qua SP)
   ------------------------------------------------------------------------
   [15] Thêm REVOKE UPDATE ON don_hang + GRANT EXECUTE trên các SP liên
        quan, ở CUỐI FILE, cho tài khoản SQL của ứng dụng web (đặt tên
        placeholder 'app_user' - CẦN đổi thành tên tài khoản thật trước khi
        chạy). Lý do: nếu không khóa, kiểm tra quyền "chỉ CHU mới được hủy"
        trong sp_HuyDonHang (mục [14]) có thể bị bỏ qua bằng cách chạy
        UPDATE don_hang trực tiếp, không qua SP.
   ======================================================================== */

CREATE DATABASE DO_AN_QLK
GO
USE DO_AN_QLK;
GO

-- ============================
-- 1. DANH MỤC & SẢN PHẨM MASTER
-- ============================
CREATE TABLE danh_muc (
    ma_danh_muc INT IDENTITY(1,1) PRIMARY KEY,             -- Mã danh mục (khóa chính)
    ma_code_danh_muc VARCHAR(20) NOT NULL UNIQUE,          -- Mã code danh mục (vd: HOU, FUR...)
    ten_danh_muc NVARCHAR(100) NOT NULL,                   -- Tên danh mục hiển thị
    trang_thai_hoat_dong BIT DEFAULT 1,                    -- 1 = đang dùng, 0 = ngừng dùng
    ngay_tao DATETIME DEFAULT GETDATE(),                   -- Ngày tạo bản ghi
    ngay_cap_nhat DATETIME DEFAULT GETDATE()               -- Ngày cập nhật gần nhất
);
GO

CREATE TABLE mau_san_pham (
    ma_mau_san_pham INT IDENTITY(1,1) PRIMARY KEY,         -- Mã sản phẩm gốc (khóa chính)
    ma_danh_muc INT NOT NULL,                              -- Thuộc danh mục nào
    ten_san_pham NVARCHAR(150) NOT NULL,                   -- Tên sản phẩm
    ma_code_ten_sp VARCHAR(50),                            -- Mã viết tắt tên sản phẩm (vd: DIA, GHE)
    mo_ta NVARCHAR(MAX),                                   -- Mô tả chi tiết sản phẩm
    duong_dan_hinh_anh VARCHAR(255),                       -- Đường dẫn ảnh sản phẩm
    gia_thi_truong DECIMAL(15,2) DEFAULT 0,                -- Giá tham chiếu thị trường
    trang_thai_hoat_dong BIT DEFAULT 1,                    -- 1 = đang dùng, 0 = ngừng dùng
    ngay_tao DATETIME DEFAULT GETDATE(),                   -- Ngày tạo bản ghi
    ngay_cap_nhat DATETIME DEFAULT GETDATE(),              -- Ngày cập nhật gần nhất
    CONSTRAINT FK_mausp_danhmuc FOREIGN KEY (ma_danh_muc) REFERENCES danh_muc(ma_danh_muc)
);
GO

CREATE TABLE thuoc_tinh (
    ma_thuoc_tinh INT IDENTITY(1,1) PRIMARY KEY,           -- Mã thuộc tính (khóa chính)
    loai_thuoc_tinh VARCHAR(30) NOT NULL,                  -- Nhóm thuộc tính (chất liệu, màu, size...)
    ten_thuoc_tinh NVARCHAR(50) NOT NULL,                  -- Tên thuộc tính hiển thị
    ma_code_thuoc_tinh VARCHAR(30) NOT NULL,               -- Mã code thuộc tính (vd: INO, WHITE)
    CONSTRAINT UK_thuoctinh_loai_ma UNIQUE (loai_thuoc_tinh, ma_code_thuoc_tinh)
);
GO

-- ============================
-- 2. LÔ HÀNG
-- ============================
CREATE TABLE lo_hang (
    ma_lo_hang INT IDENTITY(1,1) PRIMARY KEY,              -- Mã lô hàng (khóa chính)
    ma_code_lo_hang VARCHAR(50) NOT NULL UNIQUE,           -- Mã code lô (định dạng YYMM)
    ngay_nhap DATE NOT NULL,                               -- Ngày nhập lô hàng
    ghi_chu NVARCHAR(MAX),                                 -- Ghi chú thêm về lô hàng
    ngay_tao DATETIME DEFAULT GETDATE()                    -- Ngày tạo bản ghi
);
GO

-- ============================
-- 3. KHU VỰC KHO
-- ============================
CREATE TABLE khu_vuc_kho (
    ma_khu_vuc INT IDENTITY(1,1) PRIMARY KEY,              -- Mã khu vực (khóa chính)
    ten_khu_vuc NVARCHAR(50) NOT NULL,                     -- Tên khu vực (vd: Khu Sofa, Khu trưng bày)
    loai_khu_vuc VARCHAR(20) NOT NULL DEFAULT 'STORAGE'
        CHECK (loai_khu_vuc IN ('STORAGE', 'DISPLAY', 'SHIPPING')),  -- Loại khu: lưu trữ/trưng bày/xuất hàng
    dien_tich_m2 DECIMAL(10,2) DEFAULT 0,                  -- Diện tích (m2), phục vụ KPI hiệu suất sử dụng kho
    trang_thai_hoat_dong BIT DEFAULT 1                     -- 1 = đang dùng, 0 = ngừng dùng
);
GO

-- ============================
-- 4. SKU & TỒN KHO
-- ============================
CREATE TABLE san_pham_sku (
    ma_sku INT IDENTITY(1,1) PRIMARY KEY,                  -- Mã SKU (khóa chính)
    ma_code_sku VARCHAR(50) NOT NULL UNIQUE,               -- Mã code SKU đầy đủ (vd: HOU-DIA-CERWHITE-2603001)
    ma_mau_san_pham INT NOT NULL,                          -- Thuộc sản phẩm gốc nào
    ma_lo_hang INT NOT NULL,                               -- Thuộc lô hàng nào
    so_thu_tu INT NOT NULL DEFAULT 1,                      -- Số thứ tự trong lô
    tom_tat_thuoc_tinh NVARCHAR(150),                      -- Mô tả gộp các thuộc tính (hiển thị nhanh)
    ma_vach VARCHAR(50),                                   -- Mã vạch/barcode (dùng để quét thêm/nhập nhanh)
    gia_von DECIMAL(15,2) NOT NULL DEFAULT 0,              -- Giá vốn của SKU
    gia_niem_yet DECIMAL(15,2) NOT NULL DEFAULT 0,         -- Giá bán niêm yết
    so_luong INT NOT NULL DEFAULT 0 CHECK (so_luong >= 0), -- Số lượng tồn hiện tại
    -- BỔ SUNG [9]: chặn giá vốn/giá niêm yết bị ghi âm
    CONSTRAINT CK_sku_gia CHECK (gia_von >= 0 AND gia_niem_yet >= 0),
    trang_thai_vong_doi VARCHAR(20) DEFAULT 'READY'
        CHECK (trang_thai_vong_doi IN ('READY', 'DISPLAY', 'SOLD', 'DISPOSED')), -- Trạng thái vòng đời sản phẩm
    ma_khu_vuc INT,                                        -- Đang nằm ở khu vực nào
    ma_vi_tri VARCHAR(50),                                 -- Vị trí cụ thể (Khu-Dãy-Vị trí)
    ngay_tao DATETIME DEFAULT GETDATE(),                   -- Ngày tạo bản ghi
    ngay_cap_nhat DATETIME DEFAULT GETDATE(),              -- Ngày cập nhật gần nhất
    CONSTRAINT FK_sku_mausp FOREIGN KEY (ma_mau_san_pham) REFERENCES mau_san_pham(ma_mau_san_pham),
    CONSTRAINT FK_sku_lohang FOREIGN KEY (ma_lo_hang) REFERENCES lo_hang(ma_lo_hang),
    CONSTRAINT FK_sku_khuvuc FOREIGN KEY (ma_khu_vuc) REFERENCES khu_vuc_kho(ma_khu_vuc) ON DELETE SET NULL,
    -- BỔ SUNG [11]: không cho 2 SKU cùng 1 lô hàng bị trùng số thứ tự
    CONSTRAINT UK_sku_lohang_thutu UNIQUE (ma_lo_hang, so_thu_tu)
);
GO

-- BỔ SUNG [11]: mã vạch phải duy nhất nếu có giá trị (cho phép NULL nên
-- dùng unique filtered index thay vì UNIQUE constraint thông thường)
CREATE UNIQUE INDEX UX_sku_mavach ON san_pham_sku(ma_vach) WHERE ma_vach IS NOT NULL;
GO

CREATE TABLE thuoc_tinh_sku (
    ma_sku INT NOT NULL,                                   -- SKU nào
    ma_thuoc_tinh INT NOT NULL,                            -- Có thuộc tính gì
    CONSTRAINT PK_thuoctinh_sku PRIMARY KEY (ma_sku, ma_thuoc_tinh),
    CONSTRAINT FK_ttsku_sku FOREIGN KEY (ma_sku) REFERENCES san_pham_sku(ma_sku) ON DELETE CASCADE,
    CONSTRAINT FK_ttsku_thuoctinh FOREIGN KEY (ma_thuoc_tinh) REFERENCES thuoc_tinh(ma_thuoc_tinh)
);
GO

-- ============================
-- 5. KHÁCH HÀNG
-- ============================
CREATE TABLE khach_hang (
    ma_khach_hang INT IDENTITY(1,1) PRIMARY KEY,           -- Mã khách hàng (khóa chính)
    ten_khach_hang NVARCHAR(150) NOT NULL,                 -- Tên khách hàng
    so_dien_thoai VARCHAR(20),                             -- Số điện thoại
    dia_chi NVARCHAR(255)                                  -- Địa chỉ
);
GO

-- ============================
-- 6. NGƯỜI DÙNG
-- ============================
CREATE TABLE nguoi_dung (
    ma_nguoi_dung INT IDENTITY(1,1) PRIMARY KEY,           -- Mã người dùng (khóa chính)
    ten_dang_nhap VARCHAR(50) NOT NULL UNIQUE,             -- Tên đăng nhập
    mat_khau_ma_hoa VARCHAR(255) NOT NULL,                 -- Mật khẩu đã mã hóa
    ho_ten NVARCHAR(100) NOT NULL,                         -- Họ tên nhân viên
    vai_tro VARCHAR(20) DEFAULT 'BAN_HANG'
        CHECK (vai_tro IN ('CHU','QUAN_LY', 'NHAN_VIEN_KHO', 'BAN_HANG', 'TAI_XE')), -- Vai trò/phân quyền
    trang_thai_hoat_dong BIT DEFAULT 1,                    -- 1 = đang làm việc
    ngay_tao DATETIME DEFAULT GETDATE(),                   -- Ngày tạo tài khoản
    ngay_cap_nhat DATETIME DEFAULT GETDATE()               -- Ngày cập nhật gần nhất
);
GO

-- ============================
-- 7. ĐƠN HÀNG
-- (Đã bỏ nguon_don theo yêu cầu giao diện; ma_khach_hang được thêm lại)
-- ============================
CREATE TABLE don_hang (
    ma_don_hang INT IDENTITY(1,1) PRIMARY KEY,             -- Mã đơn hàng (khóa chính)
    ma_code_don_hang VARCHAR(30) NOT NULL UNIQUE,          -- Mã code đơn hàng hiển thị
    ma_khach_hang INT NULL,                                -- Khách hàng mua đơn (có thể để trống nếu khách vãng lai)
    ma_nhan_vien INT,                                      -- Nhân viên phụ trách đơn
    ma_khuyen_mai INT NULL,                                -- Chương trình khuyến mãi áp dụng (nếu có)
    ngay_dat_hang DATETIME2 DEFAULT GETDATE(),             -- Ngày giờ tạo đơn
    -- BỔ SUNG [13]: bỏ trạng thái DRAFT (không còn tác dụng - sp_TaoDonHang
    -- luôn tạo đơn thẳng ở CONFIRMED, DRAFT chưa từng thực sự được dùng).
    -- Đổi mặc định sang CONFIRMED vì đây là trạng thái thực tế khi đơn được tạo.
    trang_thai VARCHAR(20) DEFAULT 'CONFIRMED'
        CHECK (trang_thai IN ('CONFIRMED', 'COMPLETED', 'CANCELLED')), -- Trạng thái đơn hàng
    trang_thai_thanh_toan VARCHAR(20) DEFAULT 'UNPAID'
        CHECK (trang_thai_thanh_toan IN ('UNPAID', 'PAID')), -- Đã thanh toán hay chưa (chỉ hủy được khi UNPAID)
    tong_tien_hang DECIMAL(15,2) NOT NULL DEFAULT 0,       -- Tổng tiền hàng trước giảm giá
    tien_giam_gia DECIMAL(15,2) NOT NULL DEFAULT 0,        -- Số tiền được giảm giá
    phi_van_chuyen DECIMAL(15,2) NOT NULL DEFAULT 0,       -- Phí vận chuyển
    thanh_tien DECIMAL(15,2) NOT NULL DEFAULT 0,           -- Tổng tiền thanh toán cuối cùng (trigger tự tính)
    ghi_chu NVARCHAR(MAX),                                 -- Ghi chú đơn hàng
    ngay_huy DATETIME NULL,                                -- Thời điểm hủy đơn (nếu có)
    ly_do_huy NVARCHAR(MAX) NULL,                          -- Lý do hủy đơn (nếu có)
    ngay_tao DATETIME DEFAULT GETDATE(),                   -- Ngày tạo bản ghi
    ngay_cap_nhat DATETIME DEFAULT GETDATE(),              -- Ngày cập nhật gần nhất
    CONSTRAINT FK_donhang_nguoidung FOREIGN KEY (ma_nhan_vien) REFERENCES nguoi_dung(ma_nguoi_dung) ON DELETE SET NULL,
    CONSTRAINT FK_donhang_khachhang FOREIGN KEY (ma_khach_hang) REFERENCES khach_hang(ma_khach_hang) ON DELETE SET NULL,
    CONSTRAINT CK_donhang_huy_chuathanhtoan
        CHECK (NOT (trang_thai = 'CANCELLED' AND trang_thai_thanh_toan = 'PAID')),
    -- BỔ SUNG [9]: chặn các cột tiền bị ghi âm
    CONSTRAINT CK_donhang_tien CHECK (
        tong_tien_hang >= 0 AND tien_giam_gia >= 0 AND
        phi_van_chuyen >= 0 AND thanh_tien >= 0
    ),
    -- BỔ SUNG [10]: không cho giảm giá vượt quá tổng tiền hàng (trước đây
    -- chỉ được sp_ApDungKhuyenMai giới hạn, UPDATE trực tiếp sẽ không bị chặn)
    CONSTRAINT CK_donhang_giamgia_hople CHECK (tien_giam_gia <= tong_tien_hang)
    -- Khóa ngoại ma_khuyen_mai -> khuyen_mai được thêm bằng ALTER TABLE ở cuối file
    -- (vì bảng khuyen_mai được tạo sau bảng don_hang)
);
GO

CREATE TABLE chi_tiet_don_hang (
    ma_chi_tiet_don INT IDENTITY(1,1) PRIMARY KEY,         -- Mã chi tiết đơn (khóa chính)
    ma_don_hang INT NOT NULL,                              -- Thuộc đơn hàng nào
    ma_sku INT NOT NULL,                                   -- Bán SKU nào
    so_luong INT NOT NULL DEFAULT 1 CHECK (so_luong > 0),  -- Số lượng bán
    don_gia DECIMAL(15,2) NOT NULL DEFAULT 0,              -- Giá bán thực tế mỗi đơn vị
    gia_von DECIMAL(15,2) NOT NULL DEFAULT 0,              -- Giá vốn tại thời điểm bán (để tính lợi nhuận)
    thanh_tien_dong DECIMAL(15,2) NOT NULL DEFAULT 0,      -- Thành tiền của dòng hàng này
    CONSTRAINT FK_cthd_donhang FOREIGN KEY (ma_don_hang) REFERENCES don_hang(ma_don_hang) ON DELETE CASCADE,
    CONSTRAINT FK_cthd_sku FOREIGN KEY (ma_sku) REFERENCES san_pham_sku(ma_sku),
    -- BỔ SUNG [9]: chặn các cột tiền bị ghi âm
    CONSTRAINT CK_cthd_tien CHECK (don_gia >= 0 AND gia_von >= 0 AND thanh_tien_dong >= 0)
);
GO

-- ============================
-- 8. KIỂM KÊ TỒN KHO
-- ============================
CREATE TABLE phieu_kiem_ke (
    ma_phieu_kiem_ke INT IDENTITY(1,1) PRIMARY KEY,        -- Mã phiếu kiểm kê (khóa chính)
    ma_code_kiem_ke VARCHAR(30) NOT NULL UNIQUE,           -- Mã code phiếu kiểm kê
    ngay_kiem_ke DATE NOT NULL,                            -- Ngày thực hiện kiểm kê
    ma_khu_vuc INT,                                        -- Kiểm kê tại khu vực nào
    nguoi_tao INT,                                         -- Người lập phiếu kiểm kê
    trang_thai VARCHAR(20) DEFAULT 'PENDING'
        CHECK (trang_thai IN ('PENDING', 'COMPLETED', 'CANCELLED')), -- Trạng thái phiếu kiểm kê
    ngay_tao DATETIME DEFAULT GETDATE(),                   -- Ngày tạo bản ghi
    CONSTRAINT FK_pkk_khuvuc FOREIGN KEY (ma_khu_vuc) REFERENCES khu_vuc_kho(ma_khu_vuc) ON DELETE SET NULL,
    CONSTRAINT FK_pkk_nguoidung FOREIGN KEY (nguoi_tao) REFERENCES nguoi_dung(ma_nguoi_dung) ON DELETE SET NULL
);
GO

CREATE TABLE chi_tiet_kiem_ke (
    ma_chi_tiet_kiem_ke INT IDENTITY(1,1) PRIMARY KEY,     -- Mã chi tiết kiểm kê (khóa chính)
    ma_phieu_kiem_ke INT NOT NULL,                         -- Thuộc phiếu kiểm kê nào
    ma_sku INT NOT NULL,                                   -- Kiểm kê SKU nào
    so_luong_he_thong INT NOT NULL DEFAULT 0,              -- Số lượng ghi nhận trên hệ thống
    so_luong_thuc_te INT NOT NULL DEFAULT 0,               -- Số lượng đếm thực tế
    chenh_lech AS (so_luong_thuc_te - so_luong_he_thong) PERSISTED, -- Chênh lệch (tự tính = thực tế - hệ thống)
    CONSTRAINT FK_ctkk_phieu FOREIGN KEY (ma_phieu_kiem_ke) REFERENCES phieu_kiem_ke(ma_phieu_kiem_ke) ON DELETE CASCADE,
    CONSTRAINT FK_ctkk_sku FOREIGN KEY (ma_sku) REFERENCES san_pham_sku(ma_sku),
    -- BỔ SUNG [9]: trước đây chỉ có so_luong_thuc_te >= 0, thiếu vế này
    CONSTRAINT CK_ctkk_soluonghethong CHECK (so_luong_he_thong >= 0)
);
GO

-- ============================
-- 9. BÁO CÁO
-- ============================
CREATE TABLE bao_cao (
    ma_bao_cao INT IDENTITY(1,1) PRIMARY KEY,              -- Mã báo cáo (khóa chính)
    ma_code_bao_cao VARCHAR(50) NOT NULL UNIQUE,           -- Mã code báo cáo (vd: BC-XNT-20260722-01)
    ten_bao_cao NVARCHAR(150) NOT NULL,                    -- Tên báo cáo
    loai_bao_cao VARCHAR(50) NOT NULL,                     -- Loại báo cáo (doanh thu, tồn kho, KPI...)
    nguoi_tao INT NULL,                                    -- Người lập/xuất báo cáo
    ngay_tao DATETIME2 DEFAULT GETDATE(),                  -- Ngày giờ lập báo cáo
    tom_tat_bo_loc NVARCHAR(MAX) NULL,                     -- Bộ lọc đã dùng (khoảng thời gian...)
    duong_dan_file VARCHAR(255) NULL,                      -- Đường dẫn file xuất (PDF/Excel)
    noi_dung_bao_cao_json NVARCHAR(MAX) NULL,              -- Nội dung/chỉ số báo cáo dạng JSON
    ghi_chu NVARCHAR(MAX) NULL,                            -- Ghi chú bổ sung
    CONSTRAINT FK_baocao_nguoidung FOREIGN KEY (nguoi_tao) REFERENCES nguoi_dung(ma_nguoi_dung) ON DELETE SET NULL
);
GO

-- ============================
-- 10. KHUYẾN MÃI
-- ============================
CREATE TABLE khuyen_mai (
    ma_khuyen_mai INT IDENTITY(1,1) PRIMARY KEY,           -- Mã khuyến mãi (khóa chính)
    ma_code_khuyen_mai VARCHAR(30) NOT NULL UNIQUE,        -- Mã code chương trình khuyến mãi
    ten_khuyen_mai NVARCHAR(150) NOT NULL,                 -- Tên đợt khuyến mãi
    loai_giam_gia VARCHAR(20) DEFAULT 'PERCENT'
        CHECK (loai_giam_gia IN ('PERCENT', 'FIXED_AMOUNT')), -- Giảm theo % hay số tiền cố định
    gia_tri_giam DECIMAL(15,2) NOT NULL DEFAULT 0,         -- Giá trị giảm (% hoặc VNĐ)
    gia_tri_don_toi_thieu DECIMAL(15,2) DEFAULT 0,         -- Giá trị đơn hàng tối thiểu để áp dụng
    ngay_bat_dau DATETIME2 NOT NULL,                       -- Ngày giờ bắt đầu khuyến mãi
    ngay_ket_thuc DATETIME2 NOT NULL,                      -- Ngày giờ kết thúc khuyến mãi
    trang_thai_hoat_dong BIT DEFAULT 1,                    -- 1 = đang áp dụng
    ngay_tao DATETIME2 DEFAULT GETDATE(),                  -- Ngày tạo bản ghi
    -- BỔ SUNG [9]: chặn giá trị giảm giá / giá trị đơn tối thiểu bị âm
    CONSTRAINT CK_khuyenmai_giatri CHECK (gia_tri_giam >= 0 AND gia_tri_don_toi_thieu >= 0),
    -- BỔ SUNG [10]: nếu giảm theo %, giá trị phải trong khoảng 0-100
    CONSTRAINT CK_khuyenmai_percent CHECK (
        loai_giam_gia <> 'PERCENT' OR (gia_tri_giam >= 0 AND gia_tri_giam <= 100)
    )
);
GO

-- ============================
-- 11. NHÀ CUNG CẤP
-- (Đã bỏ tag, website, mã số thuế, số fax theo yêu cầu giao diện)
-- ============================
CREATE TABLE nha_cung_cap (
    ma_nha_cung_cap INT IDENTITY(1,1) PRIMARY KEY,         -- Mã nhà cung cấp (khóa chính)
    ma_code_ncc VARCHAR(30) NOT NULL UNIQUE,               -- Mã code nhà cung cấp
    ten_nha_cung_cap NVARCHAR(150) NOT NULL,               -- Tên nhà cung cấp
    so_dien_thoai VARCHAR(20),                             -- Số điện thoại liên hệ
    dia_chi NVARCHAR(255),                                 -- Địa chỉ nhà cung cấp
    trang_thai_hoat_dong BIT DEFAULT 1,                    -- 1 = đang hợp tác
    ngay_tao DATETIME2 DEFAULT GETDATE()                   -- Ngày tạo bản ghi
);
GO

-- ============================
-- 12. PHIẾU NHẬP KHO
-- ============================
CREATE TABLE phieu_nhap_kho (
    ma_phieu_nhap INT IDENTITY(1,1) PRIMARY KEY,           -- Mã phiếu nhập (khóa chính)
    ma_code_phieu_nhap VARCHAR(30) NOT NULL UNIQUE,        -- Mã code phiếu nhập / số ASN
    ma_nha_cung_cap INT NULL,                              -- Nhập từ nhà cung cấp nào
    nguoi_tao INT NULL,                                    -- Người lập phiếu nhập
    ngay_nhap DATETIME2 DEFAULT GETDATE(),                 -- Ngày giờ thực nhập kho
    trang_thai VARCHAR(20) DEFAULT 'PENDING'
        CHECK (trang_thai IN ('PENDING', 'RECEIVING', 'COMPLETED', 'CANCELLED')), -- Trạng thái phiếu nhập
    ghi_chu NVARCHAR(MAX) NULL,                            -- Ghi chú phiếu nhập
    ngay_tao DATETIME2 DEFAULT GETDATE(),                  -- Ngày tạo bản ghi
    tong_tien_hang DECIMAL(15,2) DEFAULT 0, -- Tổng giá trị tiền trị giá nhập kho (Tổng cộng từ các dòng chi tiết)


    CONSTRAINT FK_phieunhap_ncc FOREIGN KEY (ma_nha_cung_cap) REFERENCES nha_cung_cap(ma_nha_cung_cap) ON DELETE SET NULL,
    CONSTRAINT FK_phieunhap_nguoidung FOREIGN KEY (nguoi_tao) REFERENCES nguoi_dung(ma_nguoi_dung) ON DELETE SET NULL
);
GO

CREATE TABLE chi_tiet_phieu_nhap_kho (
    ma_chi_tiet_phieu_nhap INT IDENTITY(1,1) PRIMARY KEY,  -- Mã chi tiết phiếu nhập (khóa chính)
    ma_phieu_nhap INT NOT NULL,                            -- Thuộc phiếu nhập nào
    ma_sku INT NOT NULL,                                   -- Nhập SKU nào
    so_luong_ke_hoach INT NOT NULL DEFAULT 0,              -- Số lượng dự kiến nhập (theo ASN)
    so_luong_thuc_nhan INT NOT NULL DEFAULT 0,             -- Số lượng thực tế nhận được
    don_gia_nhap DECIMAL(15,2) DEFAULT 0,                  -- Đơn giá nhập
    thanh_tien AS (so_luong_thuc_nhan * don_gia_nhap) PERSISTED, -- Lưu thành tiền của phiếu đó (cột tính toán)
    CONSTRAINT FK_ctpn_phieunhap FOREIGN KEY (ma_phieu_nhap) REFERENCES phieu_nhap_kho(ma_phieu_nhap) ON DELETE CASCADE,
    CONSTRAINT FK_ctpn_sku FOREIGN KEY (ma_sku) REFERENCES san_pham_sku(ma_sku),
    -- BỔ SUNG [9]: chặn số lượng/đơn giá bị ghi âm
    CONSTRAINT CK_ctpn_soluong CHECK (
        so_luong_ke_hoach >= 0 AND so_luong_thuc_nhan >= 0 AND don_gia_nhap >= 0
    )
);
GO

-- ============================
-- 13. LIÊN KẾT KHÓA NGOẠI KHUYẾN MÃI CHO ĐƠN HÀNG
-- Thêm sau vì bảng khuyen_mai được tạo sau bảng don_hang
-- ============================
ALTER TABLE don_hang
ADD CONSTRAINT FK_donhang_khuyenmai FOREIGN KEY (ma_khuyen_mai)
    REFERENCES khuyen_mai(ma_khuyen_mai) ON DELETE SET NULL;
GO

-- Ràng buộc bổ sung: ngày kết thúc khuyến mãi phải sau ngày bắt đầu
ALTER TABLE khuyen_mai
ADD CONSTRAINT CK_khuyenmai_thoigian CHECK (ngay_ket_thuc > ngay_bat_dau);
GO

-- Ràng buộc bổ sung: số lượng thực tế kiểm kê không được âm
ALTER TABLE chi_tiet_kiem_ke
ADD CONSTRAINT CK_ctkk_soluongthucte CHECK (so_luong_thuc_te >= 0);
GO

-- ========================================================================
-- INDEX BỔ SUNG cho các cột khóa ngoại / cột thường lọc-join trong báo cáo.
-- SQL Server CHỈ tự tạo index cho PRIMARY KEY và UNIQUE, KHÔNG tự tạo cho
-- FOREIGN KEY hay các cột WHERE/JOIN/ORDER BY thông thường -> cần tạo tay.
-- ========================================================================
CREATE INDEX IX_donhang_ngaydathang ON don_hang(ngay_dat_hang);              -- lọc báo cáo theo khoảng ngày
CREATE INDEX IX_donhang_trangthai ON don_hang(trang_thai);                   -- lọc đơn COMPLETED/CANCELLED
CREATE INDEX IX_donhang_makhachhang ON don_hang(ma_khach_hang);
CREATE INDEX IX_donhang_manhanvien ON don_hang(ma_nhan_vien);

CREATE INDEX IX_cthd_madonhang ON chi_tiet_don_hang(ma_don_hang);            -- join lấy chi tiết theo đơn
CREATE INDEX IX_cthd_masku ON chi_tiet_don_hang(ma_sku);                     -- top sản phẩm bán chạy

CREATE INDEX IX_sku_khuvuc ON san_pham_sku(ma_khu_vuc);                      -- lọc tồn kho theo khu vực
CREATE INDEX IX_sku_trangthai ON san_pham_sku(trang_thai_vong_doi);          -- lọc SKU hết hàng/sẵn sàng
CREATE INDEX IX_sku_mausanpham ON san_pham_sku(ma_mau_san_pham);
CREATE INDEX IX_sku_lohang ON san_pham_sku(ma_lo_hang);

CREATE INDEX IX_ctkk_phieukiemke ON chi_tiet_kiem_ke(ma_phieu_kiem_ke);
CREATE INDEX IX_ctpn_phieunhap ON chi_tiet_phieu_nhap_kho(ma_phieu_nhap);
GO


/* ========================================================================
   PHẦN TRIGGER
   ======================================================================== */

-- ------------------------------------------------------------------------
-- TRG 1: Tự tính lại thanh_tien mỗi khi don_hang được update
-- (tong_tien_hang, tien_giam_gia, phi_van_chuyen thay đổi)
-- ------------------------------------------------------------------------
CREATE TRIGGER trg_donhang_capnhat_thanhtien
ON don_hang
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    -- Tránh đệ quy vô hạn vì trigger cũng UPDATE chính bảng don_hang.
    -- Dùng TRIGGER_NESTLEVEL(object_id) thay vì TRIGGER_NESTLEVEL() không tham số:
    -- bản không tham số đếm TẤT CẢ trigger đang lồng nhau (kể cả trigger của bảng khác),
    -- nên nếu don_hang bị UPDATE từ bên trong 1 trigger khác thì trigger này sẽ bị chặn oan.
    -- Bản có tham số chỉ đếm số lần CHÍNH trigger này được gọi lồng -> chỉ chặn đúng trường hợp tự đệ quy.
    IF TRIGGER_NESTLEVEL(OBJECT_ID('trg_donhang_capnhat_thanhtien')) > 1 RETURN;

    UPDATE dh
    SET dh.thanh_tien = i.tong_tien_hang - i.tien_giam_gia + i.phi_van_chuyen,
        dh.ngay_cap_nhat = GETDATE()
    FROM don_hang dh
    INNER JOIN inserted i ON dh.ma_don_hang = i.ma_don_hang;
END;
GO

-- ------------------------------------------------------------------------
-- TRG 2: Tự cập nhật ngay_cap_nhat cho san_pham_sku khi có thay đổi
-- (SQL Server không tự có ON UPDATE như MySQL)
-- ------------------------------------------------------------------------
CREATE TRIGGER trg_sku_ngaycapnhat
ON san_pham_sku
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    -- QUAN TRỌNG: dùng TRIGGER_NESTLEVEL(object_id) thay vì TRIGGER_NESTLEVEL() trơn.
    -- Lý do: san_pham_sku còn bị UPDATE gián tiếp từ trg_cthd_tru_ton_khi_ban (trừ tồn khi bán)
    -- và trg_donhang_hoan_ton_khi_huy (hoàn tồn khi hủy đơn). Khi đó trigger này được gọi
    -- LỒNG từ 1 trigger khác (không phải tự gọi lại chính nó), nên TRIGGER_NESTLEVEL() > 1
    -- vẫn đúng nhưng KHÔNG phải là đệ quy của chính trigger này -> nếu chặn sẽ làm
    -- ngay_cap_nhat không được cập nhật mỗi khi bán/hủy đơn (bug). Dùng bản có tham số
    -- object_id để chỉ đếm số lần CHÍNH trigger trg_sku_ngaycapnhat được gọi lồng.
    IF TRIGGER_NESTLEVEL(OBJECT_ID('trg_sku_ngaycapnhat')) > 1 RETURN;

    UPDATE sp
    SET sp.ngay_cap_nhat = GETDATE()
    FROM san_pham_sku sp
    INNER JOIN inserted i ON sp.ma_sku = i.ma_sku;
END;
GO

-- ------------------------------------------------------------------------
-- TRG 3: Khi thêm dòng vào chi_tiet_don_hang -> trừ tồn kho SKU
-- Nếu tồn kho về 0 thì tự chuyển trạng thái sang SOLD
-- Nếu không đủ tồn kho thì rollback (chặn bán vượt tồn)
-- ------------------------------------------------------------------------
CREATE TRIGGER trg_cthd_tru_ton_khi_ban
ON chi_tiet_don_hang
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;
    -- SET XACT_ABORT ON để đảm bảo: nếu RAISERROR severity 16 xảy ra bên dưới,
    -- transaction hiện tại chắc chắn bị "doom" (không thể commit), bất kể phiên gọi
    -- vào (session của caller) có bật XACT_ABORT hay không.
    SET XACT_ABORT ON;

    -- BỔ SUNG: chặn insert chi_tiet_don_hang vào đơn hàng đã CANCELLED/COMPLETED.
    -- Lý do: nếu ai đó insert thẳng vào bảng này (ngoài sp_TaoDonHang), ví dụ cho
    -- 1 đơn đã hủy, trigger vẫn sẽ trừ kho một cách vô lý vì trước đây không có
    -- điều kiện nào kiểm tra trang_thai của đơn hàng liên quan.
    IF EXISTS (
        SELECT 1
        FROM inserted i
        INNER JOIN don_hang dh ON dh.ma_don_hang = i.ma_don_hang
        -- BỔ SUNG [13]: bỏ DRAFT khỏi điều kiện (đã loại bỏ trạng thái DRAFT),
    -- giờ chỉ còn CONFIRMED là trạng thái hợp lệ để thêm dòng chi tiết.
    WHERE dh.trang_thai <> 'CONFIRMED'
    )
    BEGIN
        RAISERROR (N'Không thể thêm sản phẩm vào đơn hàng đã hủy hoặc đã hoàn tất.', 16, 1);
        RETURN;
    END

    -- Gộp số lượng bán theo từng SKU trước khi kiểm tra/trừ tồn.
    -- Lý do: nếu 1 đơn hàng có 2 dòng chi tiết cùng trỏ tới 1 ma_sku, thì UPDATE ... FROM
    -- (bản gốc) chỉ áp dụng 1 trong các dòng khớp cho mỗi ma_sku (SQL Server không tự
    -- cộng dồn khi JOIN nhiều-nhiều trong UPDATE FROM), dẫn tới trừ tồn thiếu/sai.
    IF EXISTS (
        SELECT 1
        FROM (SELECT ma_sku, SUM(so_luong) AS tong_so_luong FROM inserted GROUP BY ma_sku) g
        INNER JOIN san_pham_sku sp ON sp.ma_sku = g.ma_sku
        WHERE sp.so_luong < g.tong_so_luong
    )
    BEGIN
        -- KHÔNG dùng ROLLBACK TRANSACTION ở đây.
        -- Nếu ROLLBACK ngay trong trigger, transaction đang mở của thủ tục gọi (vd sp_TaoDonHang)
        -- sẽ bị đóng đột ngột và khối TRY/CATCH bên ngoài không nhận được lỗi theo cách
        -- mong đợi (có thể phát sinh lỗi 266 "mismatching transaction count").
        -- Chỉ cần RAISERROR + RETURN: nhờ XACT_ABORT ON, transaction sẽ tự động bị
        -- đánh dấu không thể commit và lỗi sẽ được ném ngược lên đúng khối CATCH của caller.
        RAISERROR (N'Số lượng bán vượt quá tồn kho hiện có của SKU.', 16, 1);
        RETURN;
    END

    -- BỔ SUNG: gộp 2 UPDATE (trừ số lượng + chuyển trạng thái SOLD) thành 1 câu lệnh
    -- duy nhất bằng CASE. Bản gốc dùng 2 UPDATE riêng biệt trên cùng bảng san_pham_sku,
    -- khiến trigger trg_sku_ngaycapnhat bị gọi lồng 2 lần không cần thiết cho cùng 1 lần bán.
    UPDATE sp
    SET sp.so_luong = sp.so_luong - g.tong_so_luong,
        sp.trang_thai_vong_doi = CASE WHEN sp.so_luong - g.tong_so_luong = 0
                                       THEN 'SOLD' ELSE sp.trang_thai_vong_doi END
    FROM san_pham_sku sp
    INNER JOIN (SELECT ma_sku, SUM(so_luong) AS tong_so_luong FROM inserted GROUP BY ma_sku) g
        ON sp.ma_sku = g.ma_sku;
END;
GO

-- ------------------------------------------------------------------------
-- TRG 4: Khi don_hang chuyển sang CANCELLED -> hoàn lại tồn kho
-- (chỉ áp dụng cho đơn chuyển trạng thái từ khác CANCELLED sang CANCELLED)
-- ------------------------------------------------------------------------
CREATE TRIGGER trg_donhang_hoan_ton_khi_huy
ON don_hang
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    -- Cùng lý do như trg_donhang_capnhat_thanhtien: dùng guard riêng cho trigger này
    -- để không bị ảnh hưởng bởi các trigger khác đang lồng nhau trên bảng khác.
    IF TRIGGER_NESTLEVEL(OBJECT_ID('trg_donhang_hoan_ton_khi_huy')) > 1 RETURN;

    IF EXISTS (
        SELECT 1 FROM inserted i
        INNER JOIN deleted d ON i.ma_don_hang = d.ma_don_hang
        WHERE i.trang_thai = 'CANCELLED' AND d.trang_thai <> 'CANCELLED'
    )
    BEGIN
        UPDATE sp
        SET sp.so_luong = sp.so_luong + ct.so_luong,
            sp.trang_thai_vong_doi = CASE WHEN sp.trang_thai_vong_doi = 'SOLD'
                                           THEN 'READY' ELSE sp.trang_thai_vong_doi END
        FROM san_pham_sku sp
        INNER JOIN chi_tiet_don_hang ct ON ct.ma_sku = sp.ma_sku
        INNER JOIN inserted i ON i.ma_don_hang = ct.ma_don_hang
        INNER JOIN deleted d ON d.ma_don_hang = i.ma_don_hang
        WHERE i.trang_thai = 'CANCELLED' AND d.trang_thai <> 'CANCELLED';
    END
END;
GO

-- ------------------------------------------------------------------------
-- BỔ SUNG [14]: Đã BỎ trigger trg_donhang_chan_huy (từng chặn tuyệt đối
-- mọi trường hợp hủy đơn, mục [12]). Lý do: quy tắc mới là VẪN CHO PHÉP
-- hủy đơn, nhưng có điều kiện chặt hơn thay vì chặn hết:
--   1) Đơn ĐÃ THANH TOÁN (PAID) thì KHÔNG được hủy - điều này KHÔNG CẦN
--      trigger riêng, vì bảng don_hang đã có sẵn CONSTRAINT
--      CK_donhang_huy_chuathanhtoan (CHECK NOT (trang_thai='CANCELLED'
--      AND trang_thai_thanh_toan='PAID')) chặn tuyệt đối ở tầng bảng rồi -
--      không ai bypass được kể cả chạy UPDATE trực tiếp.
--   2) CHỈ "ông chủ" (vai_tro = 'CHU') mới có quyền hủy - quy tắc này CẦN
--      biết ai đang thực hiện thao tác, mà trigger không có thông tin đó
--      (đúng theo hướng đã chọn trước đây: xử lý phân quyền ở tầng ứng
--      dụng). Vì vậy được kiểm tra trong sp_HuyDonHang thông qua tham số
--      @ma_nguoi_thuc_hien do tầng web truyền vào (lấy từ Session).
-- HỆ QUẢ: trigger trg_donhang_hoan_ton_khi_huy (hoàn kho khi hủy) giờ
-- HOẠT ĐỘNG TRỞ LẠI bình thường, vì đơn chưa thanh toán lại có thể được
-- hủy qua sp_HuyDonHang.
-- ------------------------------------------------------------------------

-- ------------------------------------------------------------------------
-- TRG 5: Khi phieu_kiem_ke chuyển sang COMPLETED -> cập nhật tồn kho
-- thực tế cho toàn bộ SKU trong phiếu đó
-- ------------------------------------------------------------------------
CREATE TRIGGER trg_kiemke_capnhat_ton
ON phieu_kiem_ke
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF TRIGGER_NESTLEVEL(OBJECT_ID('trg_kiemke_capnhat_ton')) > 1 RETURN;

    IF EXISTS (
        SELECT 1 FROM inserted i
        INNER JOIN deleted d ON i.ma_phieu_kiem_ke = d.ma_phieu_kiem_ke
        WHERE i.trang_thai = 'COMPLETED' AND d.trang_thai <> 'COMPLETED'
    )
    BEGIN
        UPDATE sp
        SET sp.so_luong = ct.so_luong_thuc_te
        FROM san_pham_sku sp
        INNER JOIN chi_tiet_kiem_ke ct ON ct.ma_sku = sp.ma_sku
        INNER JOIN inserted i ON i.ma_phieu_kiem_ke = ct.ma_phieu_kiem_ke
        INNER JOIN deleted d ON d.ma_phieu_kiem_ke = i.ma_phieu_kiem_ke
        WHERE i.trang_thai = 'COMPLETED' AND d.trang_thai <> 'COMPLETED';
    END
END;
GO

-- ------------------------------------------------------------------------
-- TRG 6: Kiểm tra tính hợp lệ của khuyến mãi khi gán vào đơn hàng
-- (còn active, còn trong thời hạn ngay_bat_dau..ngay_ket_thuc, đơn hàng
-- đạt gia_tri_don_toi_thieu). Chỉ kiểm tra khi cột ma_khuyen_mai được
-- GÁN MỚI/THAY ĐỔI (dùng UPDATE(ma_khuyen_mai)), KHÔNG kiểm tra lại mỗi
-- lần đơn hàng được update vì lý do khác -> tránh trường hợp 1 đơn hàng
-- cũ tự nhiên bị lỗi "khuyến mãi hết hạn" khi chỉ đang sửa ghi_chu, v.v.
-- ------------------------------------------------------------------------
CREATE TRIGGER trg_donhang_kiemtra_khuyenmai
ON don_hang
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF TRIGGER_NESTLEVEL(OBJECT_ID('trg_donhang_kiemtra_khuyenmai')) > 1 RETURN;
    IF NOT UPDATE(ma_khuyen_mai) RETURN;

    IF EXISTS (
        SELECT 1
        FROM inserted i
        WHERE i.ma_khuyen_mai IS NOT NULL
          AND NOT EXISTS (
              SELECT 1 FROM khuyen_mai km
              WHERE km.ma_khuyen_mai = i.ma_khuyen_mai
                AND km.trang_thai_hoat_dong = 1
                AND i.ngay_dat_hang BETWEEN km.ngay_bat_dau AND km.ngay_ket_thuc
                AND i.tong_tien_hang >= km.gia_tri_don_toi_thieu
          )
    )
    BEGIN
        RAISERROR (N'Khuyến mãi không hợp lệ: đã hết hạn, chưa được kích hoạt, hoặc đơn hàng chưa đạt giá trị tối thiểu để áp dụng.', 16, 1);
        RETURN;
    END
END;
GO

-- ------------------------------------------------------------------------
-- TRG 7: Tự tính lại tong_tien_hang của phiếu nhập kho mỗi khi chi tiết
-- phiếu nhập (chi_tiet_phieu_nhap_kho) thay đổi (thêm/sửa/xóa dòng)
-- ------------------------------------------------------------------------
CREATE TRIGGER trg_phieunhap_capnhat_tongtien
ON chi_tiet_phieu_nhap_kho
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE pn
    SET pn.tong_tien_hang = ISNULL((
            SELECT SUM(ct.thanh_tien)
            FROM chi_tiet_phieu_nhap_kho ct
            WHERE ct.ma_phieu_nhap = pn.ma_phieu_nhap
        ), 0)
    FROM phieu_nhap_kho pn
    WHERE pn.ma_phieu_nhap IN (
        SELECT ma_phieu_nhap FROM inserted
        UNION
        SELECT ma_phieu_nhap FROM deleted
    );
END;
GO


-- ------------------------------------------------------------------------
-- TRG 8 (MỚI): Hoàn lại tồn kho khi 1 dòng chi_tiet_don_hang bị XÓA trực tiếp
-- (sửa/xóa nhầm dòng hàng mà KHÔNG hủy cả đơn qua sp_HuyDonHang).
-- Trước đây chỉ có trg_donhang_hoan_ton_khi_huy xử lý hoàn kho khi hủy CẢ đơn,
-- còn xóa riêng 1 dòng chi tiết thì tồn kho không được hoàn -> sai lệch dữ liệu.
-- ------------------------------------------------------------------------
CREATE TRIGGER trg_cthd_hoan_ton_khi_xoa_dong
ON chi_tiet_don_hang
AFTER DELETE
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    -- QUAN TRỌNG: KHÔNG hoàn kho nếu đơn hàng liên quan đã CANCELLED, vì
    -- trg_donhang_hoan_ton_khi_huy đã hoàn kho cho TOÀN BỘ dòng của đơn đó
    -- ngay tại thời điểm hủy đơn (đơn CANCELLED nhưng các dòng chi_tiet_don_hang
    -- vẫn còn trong bảng để lưu lịch sử). Nếu không loại trừ trường hợp này,
    -- xóa dòng của 1 đơn đã hủy (dọn dữ liệu) sẽ khiến kho bị cộng 2 lần.
    UPDATE sp
    SET sp.so_luong = sp.so_luong + g.tong_so_luong,
        sp.trang_thai_vong_doi = CASE WHEN sp.trang_thai_vong_doi = 'SOLD'
                                       THEN 'READY' ELSE sp.trang_thai_vong_doi END
    FROM san_pham_sku sp
    INNER JOIN (
        SELECT d.ma_sku, SUM(d.so_luong) AS tong_so_luong
        FROM deleted d
        LEFT JOIN don_hang dh ON dh.ma_don_hang = d.ma_don_hang
        WHERE dh.ma_don_hang IS NULL OR dh.trang_thai <> 'CANCELLED'
        GROUP BY d.ma_sku
    ) g ON sp.ma_sku = g.ma_sku;
END;
GO


-- ------------------------------------------------------------------------
-- TRG 9 (MỚI): Tự động snapshot so_luong_he_thong = tồn kho hiện tại của SKU
-- ngay tại thời điểm tạo dòng kiểm kê, KHÔNG cho phép nhân viên tự nhập tay.
-- Lý do: cột so_luong_he_thong để trống/nhập tay rất dễ sai hoặc bị bỏ mặc
-- định = 0, khiến chenh_lech (cột tính toán) sai hoàn toàn và làm mất ý
-- nghĩa đối chiếu của phiếu kiểm kê. Giá trị "hệ thống" đúng nghĩa phải LUÔN
-- lấy từ dữ liệu hệ thống, không phải do người nhập.
-- ------------------------------------------------------------------------
CREATE TRIGGER trg_ctkk_snapshot_hethong
ON chi_tiet_kiem_ke
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;
    IF TRIGGER_NESTLEVEL(OBJECT_ID('trg_ctkk_snapshot_hethong')) > 1 RETURN;

    UPDATE ct
    SET ct.so_luong_he_thong = sp.so_luong
    FROM chi_tiet_kiem_ke ct
    INNER JOIN inserted i ON ct.ma_chi_tiet_kiem_ke = i.ma_chi_tiet_kiem_ke
    INNER JOIN san_pham_sku sp ON sp.ma_sku = i.ma_sku;
END;
GO


/* ========================================================================
   PHẦN STORED PROCEDURE
   ======================================================================== */

-- ------------------------------------------------------------------------
-- SP 1: Tạo đơn hàng + chi tiết đơn trong 1 transaction
-- Tham số @chi_tiet dạng bảng (table type) danh sách SKU cần bán
-- ------------------------------------------------------------------------
CREATE TYPE ChiTietDonHang_Type AS TABLE
(
    ma_sku INT,
    so_luong INT,
    don_gia DECIMAL(15,2)
);
GO

CREATE PROCEDURE sp_TaoDonHang
    @ma_code_don_hang VARCHAR(30),
    @ma_nhan_vien INT,
    @ma_khach_hang INT = NULL,
    @ma_khuyen_mai INT = NULL,
    @tien_giam_gia DECIMAL(15,2) = 0,
    @phi_van_chuyen DECIMAL(15,2) = 0,
    @ghi_chu NVARCHAR(MAX) = NULL,
    @chi_tiet ChiTietDonHang_Type READONLY
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        DECLARE @ma_don_hang INT;
        DECLARE @tong_tien_hang DECIMAL(15,2);

        SELECT @tong_tien_hang = SUM(so_luong * don_gia) FROM @chi_tiet;

        INSERT INTO don_hang (ma_code_don_hang, ma_nhan_vien, ma_khach_hang, ma_khuyen_mai,
                               tong_tien_hang, tien_giam_gia, phi_van_chuyen,
                               ghi_chu, trang_thai, trang_thai_thanh_toan)
        VALUES (@ma_code_don_hang, @ma_nhan_vien, @ma_khach_hang, @ma_khuyen_mai,
                @tong_tien_hang, @tien_giam_gia, @phi_van_chuyen,
                @ghi_chu, 'CONFIRMED', 'UNPAID');

        SET @ma_don_hang = SCOPE_IDENTITY();

        -- Chèn chi tiết đơn; trigger trg_cthd_tru_ton_khi_ban sẽ tự trừ kho
        INSERT INTO chi_tiet_don_hang (ma_don_hang, ma_sku, so_luong, don_gia, gia_von, thanh_tien_dong)
        SELECT @ma_don_hang, ct.ma_sku, ct.so_luong, ct.don_gia, sp.gia_von,
               ct.so_luong * ct.don_gia
        FROM @chi_tiet ct
        INNER JOIN san_pham_sku sp ON sp.ma_sku = ct.ma_sku;

        COMMIT TRANSACTION;
        SELECT @ma_don_hang AS ma_don_hang_moi;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO

-- ------------------------------------------------------------------------
-- SP 2: Hủy đơn hàng
-- BỔ SUNG [14]: Chỉ "ông chủ" (vai_tro = 'CHU') mới có quyền hủy đơn, và
-- chỉ hủy được đơn CHƯA thanh toán (UNPAID). Đơn đã PAID không thể hủy dù
-- là ông chủ hay ai đi nữa - phần này còn được bảo vệ thêm ở tầng bảng bởi
-- CONSTRAINT CK_donhang_huy_chuathanhtoan (không thể bypass).
-- @ma_nguoi_thuc_hien: mã người dùng đang thực hiện thao tác hủy, tầng web
-- PHẢI truyền vào giá trị lấy từ Session (người đang đăng nhập), không cho
-- phép người dùng tự nhập tùy ý.
-- ------------------------------------------------------------------------
CREATE PROCEDURE sp_HuyDonHang
    @ma_don_hang INT,
    @ma_nguoi_thuc_hien INT,
    @ly_do_huy NVARCHAR(MAX) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @trang_thai_tt VARCHAR(20);
    SELECT @trang_thai_tt = trang_thai_thanh_toan FROM don_hang WHERE ma_don_hang = @ma_don_hang;

    IF @trang_thai_tt IS NULL
    BEGIN
        RAISERROR (N'Không tìm thấy đơn hàng.', 16, 1);
        RETURN;
    END

    -- Kiểm tra quyền: chỉ ông chủ (CHU) mới được hủy đơn
    IF NOT EXISTS (
        SELECT 1 FROM nguoi_dung
        WHERE ma_nguoi_dung = @ma_nguoi_thuc_hien AND vai_tro = 'CHU'
    )
    BEGIN
        RAISERROR (N'Chỉ có ông chủ mới có quyền hủy đơn hàng.', 16, 1);
        RETURN;
    END

    -- Kiểm tra đã thanh toán chưa
    IF @trang_thai_tt = 'PAID'
    BEGIN
        RAISERROR (N'Đơn hàng đã thanh toán, không thể hủy.', 16, 1);
        RETURN;
    END

    -- Trigger trg_donhang_hoan_ton_khi_huy sẽ tự hoàn kho khi trạng thái đổi sang CANCELLED
    UPDATE don_hang
    SET trang_thai = 'CANCELLED',
        ngay_huy = GETDATE(),
        ly_do_huy = @ly_do_huy
    WHERE ma_don_hang = @ma_don_hang;
END;
GO

-- ------------------------------------------------------------------------
-- SP 3: Quét mã SKU/barcode để nhập nhanh vào kho (tăng tồn kho)
-- Nếu SKU chưa tồn tại thì báo lỗi (cần tạo SKU trước qua màn hình thêm SP)
-- ------------------------------------------------------------------------
CREATE PROCEDURE sp_QuetSkuNhapKho
    @ma_vach_hoac_sku VARCHAR(50),
    @so_luong_them INT,
    @ma_khu_vuc INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @ma_sku INT;
    SELECT @ma_sku = ma_sku
    FROM san_pham_sku
    WHERE ma_vach = @ma_vach_hoac_sku OR ma_code_sku = @ma_vach_hoac_sku;

    IF @ma_sku IS NULL
    BEGIN
        RAISERROR (N'Không tìm thấy SKU/mã vạch này trong hệ thống. Vui lòng tạo sản phẩm trước.', 16, 1);
        RETURN;
    END

    IF @so_luong_them <= 0
    BEGIN
        RAISERROR (N'Số lượng thêm phải lớn hơn 0.', 16, 1);
        RETURN;
    END

    UPDATE san_pham_sku
    SET so_luong = so_luong + @so_luong_them,
        ma_khu_vuc = COALESCE(@ma_khu_vuc, ma_khu_vuc),
        trang_thai_vong_doi = CASE WHEN trang_thai_vong_doi = 'SOLD'
                                    THEN 'READY' ELSE trang_thai_vong_doi END
    WHERE ma_sku = @ma_sku;

    SELECT ma_sku, ma_code_sku, so_luong AS ton_kho_sau_khi_them
    FROM san_pham_sku WHERE ma_sku = @ma_sku;
END;
GO

-- ------------------------------------------------------------------------
-- SP 4: Báo cáo doanh thu theo thời gian - nhóm theo Ngày/Tuần/Tháng/Năm
-- Trả về đúng 3 cột: mốc thời gian, số lượng đơn, doanh thu
-- ------------------------------------------------------------------------
CREATE PROCEDURE sp_BaoCaoDoanhThuTheoThoiGian
    @tu_ngay DATE,
    @den_ngay DATE,
    @nhom_theo VARCHAR(10) = 'NGAY'   -- NGAY | TUAN | THANG | NAM
AS
BEGIN
    SET NOCOUNT ON;

    IF @nhom_theo = 'NGAY'
        SELECT
            CAST(ngay_dat_hang AS DATE) AS moc_thoi_gian,
            COUNT(DISTINCT ma_don_hang) AS so_luong_don,
            SUM(thanh_tien) AS doanh_thu
        FROM don_hang
        WHERE trang_thai = 'COMPLETED'
          AND CAST(ngay_dat_hang AS DATE) BETWEEN @tu_ngay AND @den_ngay
        GROUP BY CAST(ngay_dat_hang AS DATE)
        ORDER BY moc_thoi_gian;

    ELSE IF @nhom_theo = 'TUAN'
        SELECT
            DATEPART(YEAR, ngay_dat_hang) AS nam,
            DATEPART(WEEK, ngay_dat_hang) AS tuan,
            COUNT(DISTINCT ma_don_hang) AS so_luong_don,
            SUM(thanh_tien) AS doanh_thu
        FROM don_hang
        WHERE trang_thai = 'COMPLETED'
          AND CAST(ngay_dat_hang AS DATE) BETWEEN @tu_ngay AND @den_ngay
        GROUP BY DATEPART(YEAR, ngay_dat_hang), DATEPART(WEEK, ngay_dat_hang)
        ORDER BY nam, tuan;

    ELSE IF @nhom_theo = 'THANG'
        SELECT
            DATEPART(YEAR, ngay_dat_hang) AS nam,
            DATEPART(MONTH, ngay_dat_hang) AS thang,
            COUNT(DISTINCT ma_don_hang) AS so_luong_don,
            SUM(thanh_tien) AS doanh_thu
        FROM don_hang
        WHERE trang_thai = 'COMPLETED'
          AND CAST(ngay_dat_hang AS DATE) BETWEEN @tu_ngay AND @den_ngay
        GROUP BY DATEPART(YEAR, ngay_dat_hang), DATEPART(MONTH, ngay_dat_hang)
        ORDER BY nam, thang;

    ELSE IF @nhom_theo = 'NAM'
        SELECT
            DATEPART(YEAR, ngay_dat_hang) AS nam,
            COUNT(DISTINCT ma_don_hang) AS so_luong_don,
            SUM(thanh_tien) AS doanh_thu
        FROM don_hang
        WHERE trang_thai = 'COMPLETED'
          AND CAST(ngay_dat_hang AS DATE) BETWEEN @tu_ngay AND @den_ngay
        GROUP BY DATEPART(YEAR, ngay_dat_hang)
        ORDER BY nam;
END;
GO

-- ------------------------------------------------------------------------
-- SP 5: Hoàn tất phiếu kiểm kê - chuyển trạng thái sang COMPLETED
-- Trigger trg_kiemke_capnhat_ton sẽ tự cập nhật tồn kho thực tế
-- ------------------------------------------------------------------------
CREATE PROCEDURE sp_HoanTatKiemKe
    @ma_phieu_kiem_ke INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @trang_thai_hien_tai VARCHAR(20);
    SELECT @trang_thai_hien_tai = trang_thai
    FROM phieu_kiem_ke WHERE ma_phieu_kiem_ke = @ma_phieu_kiem_ke;

    IF @trang_thai_hien_tai IS NULL
    BEGIN
        RAISERROR (N'Không tìm thấy phiếu kiểm kê.', 16, 1);
        RETURN;
    END

    -- BỔ SUNG: chặn hoàn tất phiếu đã CANCELLED (không hợp lý khi cập nhật tồn kho
    -- theo 1 phiếu đã bị hủy) và chặn hoàn tất lại phiếu đã COMPLETED (tránh chạy
    -- trùng, dù trigger trg_kiemke_capnhat_ton đã có điều kiện idempotent riêng).
    IF @trang_thai_hien_tai = 'CANCELLED'
    BEGIN
        RAISERROR (N'Phiếu kiểm kê này đã bị hủy, không thể hoàn tất.', 16, 1);
        RETURN;
    END

    IF @trang_thai_hien_tai = 'COMPLETED'
    BEGIN
        RAISERROR (N'Phiếu kiểm kê này đã được hoàn tất trước đó.', 16, 1);
        RETURN;
    END

    UPDATE phieu_kiem_ke
    SET trang_thai = 'COMPLETED'
    WHERE ma_phieu_kiem_ke = @ma_phieu_kiem_ke;

    SELECT sp.ma_sku, sp.ma_code_sku, ct.so_luong_he_thong, ct.so_luong_thuc_te, ct.chenh_lech
    FROM chi_tiet_kiem_ke ct
    INNER JOIN san_pham_sku sp ON sp.ma_sku = ct.ma_sku
    WHERE ct.ma_phieu_kiem_ke = @ma_phieu_kiem_ke;
END;
GO

-- ------------------------------------------------------------------------
-- SP 6: Áp dụng mã khuyến mãi cho 1 đơn hàng đã tồn tại.
-- Tự tính tien_giam_gia theo loai_giam_gia (PERCENT/FIXED_AMOUNT), không
-- cho giảm vượt quá tong_tien_hang. Trigger trg_donhang_kiemtra_khuyenmai
-- sẽ validate lại (còn hạn/còn active/đủ giá trị tối thiểu), trigger
-- trg_donhang_capnhat_thanhtien sẽ tự tính lại thanh_tien sau khi UPDATE.
-- ------------------------------------------------------------------------
CREATE PROCEDURE sp_ApDungKhuyenMai
    @ma_don_hang INT,
    @ma_code_khuyen_mai VARCHAR(30)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @ma_khuyen_mai INT, @loai_giam_gia VARCHAR(20), @gia_tri_giam DECIMAL(15,2),
            @gia_tri_toi_thieu DECIMAL(15,2), @dang_active BIT,
            @ngay_bat_dau DATETIME2, @ngay_ket_thuc DATETIME2;

    SELECT @ma_khuyen_mai = ma_khuyen_mai, @loai_giam_gia = loai_giam_gia,
           @gia_tri_giam = gia_tri_giam, @gia_tri_toi_thieu = gia_tri_don_toi_thieu,
           @dang_active = trang_thai_hoat_dong, @ngay_bat_dau = ngay_bat_dau,
           @ngay_ket_thuc = ngay_ket_thuc
    FROM khuyen_mai
    WHERE ma_code_khuyen_mai = @ma_code_khuyen_mai;

    IF @ma_khuyen_mai IS NULL
    BEGIN
        RAISERROR (N'Không tìm thấy mã khuyến mãi.', 16, 1);
        RETURN;
    END

    IF @dang_active = 0 OR GETDATE() NOT BETWEEN @ngay_bat_dau AND @ngay_ket_thuc
    BEGIN
        RAISERROR (N'Khuyến mãi chưa được kích hoạt hoặc đã hết hạn.', 16, 1);
        RETURN;
    END

    DECLARE @tong_tien_hang DECIMAL(15,2);
    SELECT @tong_tien_hang = tong_tien_hang FROM don_hang WHERE ma_don_hang = @ma_don_hang;

    IF @tong_tien_hang IS NULL
    BEGIN
        RAISERROR (N'Không tìm thấy đơn hàng.', 16, 1);
        RETURN;
    END

    IF @tong_tien_hang < @gia_tri_toi_thieu
    BEGIN
        RAISERROR (N'Đơn hàng chưa đạt giá trị tối thiểu để áp dụng khuyến mãi này.', 16, 1);
        RETURN;
    END

    DECLARE @tien_giam DECIMAL(15,2);
    IF @loai_giam_gia = 'PERCENT'
        SET @tien_giam = @tong_tien_hang * @gia_tri_giam / 100.0;
    ELSE
        SET @tien_giam = @gia_tri_giam;

    -- Không để số tiền giảm vượt quá tổng tiền hàng
    IF @tien_giam > @tong_tien_hang SET @tien_giam = @tong_tien_hang;

    UPDATE don_hang
    SET ma_khuyen_mai = @ma_khuyen_mai,
        tien_giam_gia = @tien_giam
    WHERE ma_don_hang = @ma_don_hang;

    SELECT ma_don_hang, ma_khuyen_mai, tien_giam_gia, thanh_tien
    FROM don_hang WHERE ma_don_hang = @ma_don_hang;
END;
GO

-- ------------------------------------------------------------------------
-- SP 7: Hoàn tất phiếu nhập kho - chuyển trạng thái sang COMPLETED và
-- CỘNG tồn kho theo so_luong_thuc_nhan của từng dòng chi tiết.
-- (Trước đây phiếu nhập kho KHÔNG có bước nào cộng tồn kho thực tế -
-- đây là thiếu sót được bổ sung, tương tự cách sp_HoanTatKiemKe /
-- trg_kiemke_capnhat_ton xử lý cho phiếu kiểm kê.)
-- ------------------------------------------------------------------------
CREATE PROCEDURE sp_HoanTatNhapKho
    @ma_phieu_nhap INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF NOT EXISTS (SELECT 1 FROM phieu_nhap_kho WHERE ma_phieu_nhap = @ma_phieu_nhap)
    BEGIN
        RAISERROR (N'Không tìm thấy phiếu nhập kho.', 16, 1);
        RETURN;
    END

    IF EXISTS (SELECT 1 FROM phieu_nhap_kho WHERE ma_phieu_nhap = @ma_phieu_nhap AND trang_thai = 'COMPLETED')
    BEGIN
        RAISERROR (N'Phiếu nhập kho này đã được hoàn tất trước đó.', 16, 1);
        RETURN;
    END

    -- BỔ SUNG: chặn hoàn tất (cộng tồn kho) cho phiếu nhập đã CANCELLED.
    IF EXISTS (SELECT 1 FROM phieu_nhap_kho WHERE ma_phieu_nhap = @ma_phieu_nhap AND trang_thai = 'CANCELLED')
    BEGIN
        RAISERROR (N'Phiếu nhập kho này đã bị hủy, không thể hoàn tất.', 16, 1);
        RETURN;
    END

    BEGIN TRY
        BEGIN TRANSACTION;

        UPDATE sp
        SET sp.so_luong = sp.so_luong + ct.so_luong_thuc_nhan,
            sp.trang_thai_vong_doi = CASE WHEN sp.trang_thai_vong_doi = 'SOLD'
                                           THEN 'READY' ELSE sp.trang_thai_vong_doi END
        FROM san_pham_sku sp
        INNER JOIN (
            SELECT ma_sku, SUM(so_luong_thuc_nhan) AS so_luong_thuc_nhan
            FROM chi_tiet_phieu_nhap_kho
            WHERE ma_phieu_nhap = @ma_phieu_nhap
            GROUP BY ma_sku
        ) ct ON ct.ma_sku = sp.ma_sku;

        UPDATE phieu_nhap_kho
        SET trang_thai = 'COMPLETED'
        WHERE ma_phieu_nhap = @ma_phieu_nhap;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH

    SELECT sp.ma_sku, sp.ma_code_sku, ct.so_luong_thuc_nhan, sp.so_luong AS ton_kho_sau_khi_nhap
    FROM chi_tiet_phieu_nhap_kho ct
    INNER JOIN san_pham_sku sp ON sp.ma_sku = ct.ma_sku
    WHERE ct.ma_phieu_nhap = @ma_phieu_nhap;
END;
GO

-- ============================================================================
-- BỔ SUNG [15]: KHÓA QUYỀN UPDATE TRỰC TIẾP TRÊN don_hang
-- ============================================================================
-- LÝ DO: sp_HuyDonHang (mục [14]) có kiểm tra vai trò (chỉ 'CHU' được hủy)
-- và trạng thái thanh toán trước khi hủy đơn. Nhưng kiểm tra đó CHỈ có tác
-- dụng nếu MỌI thay đổi trạng thái đơn hàng đều bắt buộc đi qua SP này.
-- Nếu tài khoản SQL mà ứng dụng web dùng để kết nối vẫn còn quyền UPDATE
-- trực tiếp trên bảng don_hang, ai đó (hoặc đoạn code khác trong app) vẫn
-- có thể chạy thẳng:
--     UPDATE don_hang SET trang_thai = 'CANCELLED' WHERE ma_don_hang = ...
-- và bỏ qua hoàn toàn kiểm tra quyền "chỉ CHU mới được hủy" trong SP.
--
-- CƠ CHẾ: SQL Server dùng "ownership chaining" - vì stored procedure và
-- bảng don_hang trong file này đều thuộc cùng 1 owner (schema mặc định
-- dbo), tài khoản chỉ cần quyền EXECUTE trên procedure là đủ để procedure
-- đó UPDATE được bảng bên trong, KHÔNG cần thêm quyền UPDATE trực tiếp
-- trên bảng. Vì vậy REVOKE dưới đây không làm hỏng các SP hiện có
-- (sp_HuyDonHang, sp_TaoDonHang, sp_ApDungKhuyenMai vẫn chạy bình thường).
--
-- ⚠️ QUAN TRỌNG - CẦN BẠN TỰ KIỂM TRA TRƯỚC KHI CHẠY:
-- Thay 'app_user' bên dưới bằng ĐÚNG tên SQL Login/User mà ứng dụng
-- ASP.NET MVC của bạn dùng để kết nối CSDL (xem trong Web.config, phần
-- <connectionStrings> -> User ID=...). Nếu chạy nhầm tên tài khoản không
-- tồn tại, các câu lệnh bên dưới sẽ báo lỗi và không có tác dụng gì.
--
-- Nếu bạn CHƯA có tài khoản SQL riêng cho ứng dụng (web đang dùng chung
-- tài khoản 'sa' hoặc tài khoản có quyền admin để kết nối), thì REVOKE
-- dưới đây sẽ KHÔNG có tác dụng thực tế, vì tài khoản admin luôn bỏ qua
-- được các quyền đã revoke. Trong trường hợp đó, việc đầu tiên cần làm là
-- tạo 1 tài khoản SQL riêng, ít quyền hơn cho ứng dụng - bỏ comment 2 dòng
-- CREATE LOGIN / CREATE USER bên dưới và tự đặt mật khẩu mạnh.
-- ============================================================================

-- Bỏ comment nếu ứng dụng CHƯA có tài khoản SQL riêng (đổi mật khẩu trước khi chạy):
-- CREATE LOGIN app_user WITH PASSWORD = N'DoiMatKhauManhODay!123';
-- CREATE USER app_user FOR LOGIN app_user;

-- Khóa quyền sửa trực tiếp trạng thái đơn hàng - buộc phải đi qua SP
REVOKE UPDATE ON don_hang FROM app_user;

-- Cấp quyền chạy các stored procedure có thao tác trên don_hang
GRANT EXECUTE ON sp_HuyDonHang TO app_user;
GRANT EXECUTE ON sp_TaoDonHang TO app_user;
GRANT EXECUTE ON sp_ApDungKhuyenMai TO app_user;
GO


/* ============================================================================
   BỔ SUNG [16]: MODULE VẬN CHUYỂN (chuyến giao hàng)
   Chạy đoạn này SAU KHI đã có toàn bộ schema gốc (cơ_sở_dữ_liệu_kho).
   Gồm 3 phần:
     1) Thêm cột hinh_thuc_nhan_hang vào don_hang (phân biệt bán tại shop /
        cần giao hàng - trước đây không có, không phân biệt được đơn "không
        cần giao" với đơn "cần giao nhưng bị bỏ sót chưa xếp chuyến").
     2) 2 bảng mới: chuyen_giao_hang (1 chuyến của 1 tài xế) và
        chi_tiet_chuyen_giao (các đơn hàng nằm trong chuyến đó).
     3) Trigger đồng bộ: khi 1 đơn được đánh dấu "đã giao" trong chuyến, tự
        động chuyển don_hang.trang_thai sang COMPLETED - tránh tình trạng
        trang_thai_giao và don_hang.trang_thai lệch nhau do quên cập nhật
        tay ở 1 trong 2 nơi.
   ========================================================================= */

-- ----------------------------------------------------------------------
-- PHẦN 1: Thêm cột phân loại hình thức nhận hàng vào don_hang
-- ----------------------------------------------------------------------
ALTER TABLE don_hang
ADD hinh_thuc_nhan_hang VARCHAR(20) NOT NULL DEFAULT 'TAI_SHOP'
    CONSTRAINT CK_donhang_hinhthuc CHECK (hinh_thuc_nhan_hang IN ('TAI_SHOP', 'GIAO_HANG'));
GO

-- ----------------------------------------------------------------------
-- PHẦN 2: Bảng chuyen_giao_hang - đại diện 1 chuyến đi của 1 tài xế
-- ----------------------------------------------------------------------
CREATE TABLE chuyen_giao_hang (
    ma_chuyen INT IDENTITY(1,1) PRIMARY KEY,               -- Mã chuyến (khóa chính)
    ma_code_chuyen VARCHAR(30) NOT NULL UNIQUE,            -- Mã code chuyến hiển thị
    ma_tai_xe INT NOT NULL,                                -- Tài xế phụ trách chuyến này
    ngay_khoi_hanh DATETIME2 NULL,                         -- Thời điểm xe xuất phát
    ngay_hoan_tat DATETIME2 NULL,                          -- Thời điểm hoàn tất cả chuyến
    trang_thai VARCHAR(20) NOT NULL DEFAULT 'DANG_CHUAN_BI'
        CHECK (trang_thai IN ('DANG_CHUAN_BI', 'DANG_GIAO', 'HOAN_TAT', 'HUY')),
    ghi_chu NVARCHAR(MAX) NULL,
    ngay_tao DATETIME2 DEFAULT GETDATE(),
    CONSTRAINT FK_chuyengiaohang_taixe FOREIGN KEY (ma_tai_xe) REFERENCES nguoi_dung(ma_nguoi_dung)
);
GO

-- Đảm bảo ma_tai_xe thực sự là tài xế (không cho gán nhầm nhân viên bán hàng...)
-- Lưu ý: CHECK constraint không cho phép sub-query trực tiếp trong SQL Server,
-- nên ràng buộc này được thực hiện bằng trigger thay vì CHECK.
GO
CREATE TRIGGER trg_chuyengiaohang_kiemtra_vaitro
ON chuyen_giao_hang
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF TRIGGER_NESTLEVEL(OBJECT_ID('trg_chuyengiaohang_kiemtra_vaitro')) > 1 RETURN;

    IF EXISTS (
        SELECT 1
        FROM inserted i
        INNER JOIN nguoi_dung nd ON nd.ma_nguoi_dung = i.ma_tai_xe
        WHERE nd.vai_tro <> 'TAI_XE'
    )
    BEGIN
        RAISERROR (N'Người được gán chỉ có thể là tài xế (vai_tro = TAI_XE).', 16, 1);
        RETURN;
    END
END;
GO

-- Index phục vụ lọc "chuyến của tài xế X" và "chuyến theo trạng thái"
CREATE INDEX IX_chuyengiaohang_taixe ON chuyen_giao_hang(ma_tai_xe);
CREATE INDEX IX_chuyengiaohang_trangthai ON chuyen_giao_hang(trang_thai);
GO

-- ----------------------------------------------------------------------
-- PHẦN 2b: Bảng chi_tiet_chuyen_giao - các đơn hàng nằm trong 1 chuyến
-- ----------------------------------------------------------------------
CREATE TABLE chi_tiet_chuyen_giao (
    ma_chuyen INT NOT NULL,                                -- Thuộc chuyến nào
    ma_don_hang INT NOT NULL,                              -- Giao đơn hàng nào
    trang_thai_giao VARCHAR(20) NOT NULL DEFAULT 'CHUA_GIAO'
        CHECK (trang_thai_giao IN ('CHUA_GIAO', 'DA_GIAO', 'GIAO_THAT_BAI')),
    ghi_chu_giao NVARCHAR(MAX) NULL,                       -- Lý do thất bại, ghi chú của tài xế...
    ngay_cap_nhat DATETIME2 DEFAULT GETDATE(),
    CONSTRAINT PK_chitietchuyengiao PRIMARY KEY (ma_chuyen, ma_don_hang),
    CONSTRAINT FK_ctcg_chuyen FOREIGN KEY (ma_chuyen) REFERENCES chuyen_giao_hang(ma_chuyen) ON DELETE CASCADE,
    CONSTRAINT FK_ctcg_donhang FOREIGN KEY (ma_don_hang) REFERENCES don_hang(ma_don_hang)
);
GO

-- Không cho 1 đơn hàng bị xếp vào 2 chuyến khác nhau cùng lúc
CREATE UNIQUE INDEX UX_ctcg_mot_don_mot_chuyen_dangchay
ON chi_tiet_chuyen_giao(ma_don_hang)
WHERE trang_thai_giao = 'CHUA_GIAO';
GO

-- Chỉ cho thêm đơn "GIAO_HANG" (không phải TAI_SHOP) vào chi_tiet_chuyen_giao
CREATE TRIGGER trg_ctcg_kiemtra_hinhthuc
ON chi_tiet_chuyen_giao
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF EXISTS (
        SELECT 1
        FROM inserted i
        INNER JOIN don_hang dh ON dh.ma_don_hang = i.ma_don_hang
        WHERE dh.hinh_thuc_nhan_hang <> 'GIAO_HANG'
    )
    BEGIN
        RAISERROR (N'Chỉ có thể xếp chuyến cho đơn hàng có hình thức GIAO_HANG.', 16, 1);
        RETURN;
    END
END;
GO

-- ----------------------------------------------------------------------
-- PHẦN 3: Trigger đồng bộ trang_thai_giao -> don_hang.trang_thai
-- ----------------------------------------------------------------------
-- Khi 1 dòng chi_tiet_chuyen_giao chuyển sang DA_GIAO, tự động chuyển
-- don_hang.trang_thai sang COMPLETED (chỉ khi đơn đang CONFIRMED, không
-- đụng tới đơn đã CANCELLED - dù thực tế đơn CANCELLED không nên còn nằm
-- trong chuyến giao, đây là phòng hờ thêm).
-- Khi GIAO_THAT_BAI: KHÔNG tự đổi trang_thai của đơn (đơn vẫn ở CONFIRMED
-- để biết là cần xử lý lại - xếp vào chuyến khác hoặc liên hệ khách), chỉ
-- lưu lại ghi_chu_giao để nhân viên biết lý do.
CREATE TRIGGER trg_ctcg_dongbo_donhang
ON chi_tiet_chuyen_giao
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF TRIGGER_NESTLEVEL(OBJECT_ID('trg_ctcg_dongbo_donhang')) > 1 RETURN;

    IF UPDATE(trang_thai_giao)
    BEGIN
        UPDATE dh
        SET dh.trang_thai = 'COMPLETED'
        FROM don_hang dh
        INNER JOIN inserted i ON i.ma_don_hang = dh.ma_don_hang
        INNER JOIN deleted d ON d.ma_don_hang = i.ma_don_hang
        WHERE i.trang_thai_giao = 'DA_GIAO'
          AND d.trang_thai_giao <> 'DA_GIAO'
          AND dh.trang_thai = 'CONFIRMED';
    END
END;
GO

-- ----------------------------------------------------------------------
-- (Gợi ý) Truy vấn kiểm tra đơn cần giao nhưng bị bỏ sót, chưa xếp chuyến
-- ----------------------------------------------------------------------
-- SELECT dh.*
-- FROM don_hang dh
-- WHERE dh.hinh_thuc_nhan_hang = 'GIAO_HANG'
--   AND dh.trang_thai = 'CONFIRMED'
--   AND NOT EXISTS (
--       SELECT 1 FROM chi_tiet_chuyen_giao ctcg WHERE ctcg.ma_don_hang = dh.ma_don_hang
--   );