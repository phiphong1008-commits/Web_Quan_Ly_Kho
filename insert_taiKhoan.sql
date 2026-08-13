USE DO_AN_QLK;
GO
 
-- Sửa lại mật khẩu bằng hash BCrypt THẬT của "123456"
-- (hash cũ trong file gốc là chuỗi giả, không khớp với bất kỳ mật khẩu nào)
UPDATE nguoi_dung
SET mat_khau_ma_hoa = '$2b$11$XfmlLLbPPKLSYf8zGkqfA.Rn71VLixSR5XgEKxe.02YFMfot1yLPu'
WHERE ten_dang_nhap IN ('admin', 'quanly01', 'taixe01');
GO
 
SELECT ma_nguoi_dung, ten_dang_nhap, ho_ten, vai_tro, trang_thai_hoat_dong
FROM nguoi_dung;
GO