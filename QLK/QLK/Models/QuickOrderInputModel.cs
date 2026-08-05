using System;
using System.Collections.Generic;

namespace QLK.Models // Đảm bảo namespace này khớp với namespace Models trong dự án của bạn
{
    // Lớp hứng dữ liệu tổng thể từ AJAX gửi lên
    public class QuickOrderInputModel
    {
        public string ma_code_don_hang { get; set; }
        public int? ma_khach_hang { get; set; }
        public decimal phi_van_chuyen { get; set; }
        public decimal tien_giam_gia { get; set; }
        public string ghi_chu { get; set; }

        // Danh sách các dòng SKU chi tiết
        public List<QuickOrderItemInputModel> chi_tiet { get; set; }
    }

    // Lớp hứng từng dòng sản phẩm SKU chọn bán
    public class QuickOrderItemInputModel
    {
        public int ma_sku { get; set; }
        public int so_luong { get; set; }
        public decimal don_gia { get; set; }
    }
}