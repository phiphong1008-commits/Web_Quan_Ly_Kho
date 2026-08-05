using QLK.Models;
using System;
using System.Collections.Generic;
using System.Data;
using System.Data.Entity;
using System.Data.SqlClient;
using System.Linq;
using System.Net;
using System.Web;
using System.Web.Mvc;

namespace QLK.Controllers
{
    public class DonHangController : Controller
    {
        private DO_AN_QLKEntities db = new DO_AN_QLKEntities();

        // GET: DonHang
        public ActionResult Index()
        {
            // 1. Lấy danh sách đơn hàng kèm theo các thông tin liên kết (Khách hàng, Khuyến mãi, Người dùng)[cite: 5]
            var don_hang = db.don_hang
                             .Include(d => d.khach_hang)
                             .Include(d => d.khuyen_mai)
                             .Include(d => d.nguoi_dung)
                             .OrderByDescending(d => d.ngay_dat_hang); // Tối ưu: Sắp xếp đơn mới nhất lên đầu[cite: 5]

            // 2. NẠP MASTER DATA CHO MODAL TẠO NHANH (GIẢI QUYẾT LỖI INVALIDOPERATIONEXCEPTION)[cite: 1]
            // Tạo danh sách Khách hàng cho Dropdown[cite: 1, 5]
            ViewBag.KhachHangList = new SelectList(db.khach_hang.ToList(), "ma_khach_hang", "ten_khach_hang"); //[cite: 5]

            // 3. (Tùy chọn) Nạp danh sách SKU sản phẩm phục vụ chọn SKU tạo nhanh[cite: 1, 5]
            var skuList = db.san_pham_sku.Where(s => s.so_luong > 0).ToList(); // Chỉ lấy SKU còn tồn kho[cite: 5]

            // Xây dựng chuỗi Option HTML sẵn để JavaScript gắn dynamic vào bảng SKU
            System.Text.StringBuilder skuOptions = new System.Text.StringBuilder();
            skuOptions.Append("<option value=''>-- Chọn SKU sản phẩm --</option>");
            foreach (var sku in skuList)
            {
                skuOptions.Append($"<option value='{sku.ma_sku}' data-price='{sku.gia_niem_yet}'>{sku.ma_code_sku} - (Tồn: {sku.so_luong})</option>"); //[cite: 5]
            }
            ViewBag.SkuOptionsJavaScript = skuOptions.ToString();

            // 4. Trả về View danh sách Đơn hàng[cite: 1]
            return View(don_hang.ToList());
        }

        // GET: DonHang/Details/5
        public ActionResult Details(int? id)
        {
            if (id == null)
            {
                return new HttpStatusCodeResult(HttpStatusCode.BadRequest);
            }
            don_hang don_hang = db.don_hang.Find(id);
            if (don_hang == null)
            {
                return HttpNotFound();
            }
            return View(don_hang);
        }

        // GET: DonHang/Create
        public ActionResult Create()
        {
            ViewBag.ma_khach_hang = new SelectList(db.khach_hang, "ma_khach_hang", "ten_khach_hang");
            ViewBag.ma_khuyen_mai = new SelectList(db.khuyen_mai, "ma_khuyen_mai", "ma_code_khuyen_mai");
            ViewBag.ma_nhan_vien = new SelectList(db.nguoi_dung, "ma_nguoi_dung", "ten_dang_nhap");
            return View();
        }

        // POST: DonHang/Create
        // To protect from overposting attacks, enable the specific properties you want to bind to, for 
        // more details see https://go.microsoft.com/fwlink/?LinkId=317598.
        [HttpPost]
        [ValidateAntiForgeryToken]
        public ActionResult Create([Bind(Include = "ma_don_hang,ma_code_don_hang,ma_khach_hang,ma_nhan_vien,ma_khuyen_mai,ngay_dat_hang,trang_thai,trang_thai_thanh_toan,tong_tien_hang,tien_giam_gia,phi_van_chuyen,thanh_tien,ghi_chu,ngay_huy,ly_do_huy,ngay_tao,ngay_cap_nhat,hinh_thuc_nhan_hang")] don_hang don_hang)
        {
            if (ModelState.IsValid)
            {
                db.don_hang.Add(don_hang);
                db.SaveChanges();
                return RedirectToAction("Index");
            }

            ViewBag.ma_khach_hang = new SelectList(db.khach_hang, "ma_khach_hang", "ten_khach_hang", don_hang.ma_khach_hang);
            ViewBag.ma_khuyen_mai = new SelectList(db.khuyen_mai, "ma_khuyen_mai", "ma_code_khuyen_mai", don_hang.ma_khuyen_mai);
            ViewBag.ma_nhan_vien = new SelectList(db.nguoi_dung, "ma_nguoi_dung", "ten_dang_nhap", don_hang.ma_nhan_vien);
            return View(don_hang);
        }

        // GET: DonHang/Edit/5
        public ActionResult Edit(int? id)
        {
            if (id == null)
            {
                return new HttpStatusCodeResult(HttpStatusCode.BadRequest);
            }
            don_hang don_hang = db.don_hang.Find(id);
            if (don_hang == null)
            {
                return HttpNotFound();
            }
            ViewBag.ma_khach_hang = new SelectList(db.khach_hang, "ma_khach_hang", "ten_khach_hang", don_hang.ma_khach_hang);
            ViewBag.ma_khuyen_mai = new SelectList(db.khuyen_mai, "ma_khuyen_mai", "ma_code_khuyen_mai", don_hang.ma_khuyen_mai);
            ViewBag.ma_nhan_vien = new SelectList(db.nguoi_dung, "ma_nguoi_dung", "ten_dang_nhap", don_hang.ma_nhan_vien);
            return View(don_hang);
        }

        // POST: DonHang/Edit/5
        // To protect from overposting attacks, enable the specific properties you want to bind to, for 
        // more details see https://go.microsoft.com/fwlink/?LinkId=317598.
        [HttpPost]
        [ValidateAntiForgeryToken]
        public ActionResult Edit([Bind(Include = "ma_don_hang,ma_code_don_hang,ma_khach_hang,ma_nhan_vien,ma_khuyen_mai,ngay_dat_hang,trang_thai,trang_thai_thanh_toan,tong_tien_hang,tien_giam_gia,phi_van_chuyen,thanh_tien,ghi_chu,ngay_huy,ly_do_huy,ngay_tao,ngay_cap_nhat,hinh_thuc_nhan_hang")] don_hang don_hang)
        {
            if (ModelState.IsValid)
            {
                db.Entry(don_hang).State = EntityState.Modified;
                db.SaveChanges();
                return RedirectToAction("Index");
            }
            ViewBag.ma_khach_hang = new SelectList(db.khach_hang, "ma_khach_hang", "ten_khach_hang", don_hang.ma_khach_hang);
            ViewBag.ma_khuyen_mai = new SelectList(db.khuyen_mai, "ma_khuyen_mai", "ma_code_khuyen_mai", don_hang.ma_khuyen_mai);
            ViewBag.ma_nhan_vien = new SelectList(db.nguoi_dung, "ma_nguoi_dung", "ten_dang_nhap", don_hang.ma_nhan_vien);
            return View(don_hang);
        }

        // GET: DonHang/Delete/5
        public ActionResult Delete(int? id)
        {
            if (id == null)
            {
                return new HttpStatusCodeResult(HttpStatusCode.BadRequest);
            }
            don_hang don_hang = db.don_hang.Find(id);
            if (don_hang == null)
            {
                return HttpNotFound();
            }
            return View(don_hang);
        }

        // POST: DonHang/Delete/5
        [HttpPost, ActionName("Delete")]
        [ValidateAntiForgeryToken]
        public ActionResult DeleteConfirmed(int id)
        {
            don_hang don_hang = db.don_hang.Find(id);
            db.don_hang.Remove(don_hang);
            db.SaveChanges();
            return RedirectToAction("Index");
        }
        [HttpPost]
        public JsonResult QuickCreate(QuickOrderInputModel model)
        {
            try
            {
                // Lấy Mã Nhân Viên đang đăng nhập từ Session
                int maNhanVien = Session["MaNhanVien"] != null ? Convert.ToInt32(Session["MaNhanVien"]) : 1;

                // Tạo DataTable khớp với Structured Type ChiTietDonHang_Type trong SQL
                DataTable dtChiTiet = new DataTable();
                dtChiTiet.Columns.Add("ma_sku", typeof(int));
                dtChiTiet.Columns.Add("so_luong", typeof(int));
                dtChiTiet.Columns.Add("don_gia", typeof(decimal));

                foreach (var item in model.chi_tiet)
                {
                    dtChiTiet.Rows.Add(item.ma_sku, item.so_luong, item.don_gia);
                }

                // Gọi Procedure CSDL bằng ADO.NET / Entity Framework
                using (var db = new DO_AN_QLKEntities())
                {
                    var paramCode = new SqlParameter("@ma_code_don_hang", model.ma_code_don_hang);
                    var paramNV = new SqlParameter("@ma_nhan_vien", maNhanVien);
                    var paramKH = new SqlParameter("@ma_khach_hang", (object)model.ma_khach_hang ?? DBNull.Value);
                    var paramKM = new SqlParameter("@ma_khuyen_mai", DBNull.Value);
                    var paramGiamGia = new SqlParameter("@tien_giam_gia", model.tien_giam_gia);
                    var paramShip = new SqlParameter("@phi_van_chuyen", model.phi_van_chuyen);
                    var paramGhiChu = new SqlParameter("@ghi_chu", (object)model.ghi_chu ?? DBNull.Value);

                    var paramChiTiet = new SqlParameter("@chi_tiet", SqlDbType.Structured)
                    {
                        TypeName = "dbo.ChiTietDonHang_Type",
                        Value = dtChiTiet
                    };

                    db.Database.ExecuteSqlCommand(
                        "EXEC sp_TaoDonHang @ma_code_don_hang, @ma_nhan_vien, @ma_khach_hang, @ma_khuyen_mai, @tien_giam_gia, @phi_van_chuyen, @ghi_chu, @chi_tiet",
                        paramCode, paramNV, paramKH, paramKM, paramGiamGia, paramShip, paramGhiChu, paramChiTiet
                    );
                }

                return Json(new { success = true, message = "Tạo đơn hàng thành công!" });
            }
            catch (Exception ex)
            {
                return Json(new { success = false, message = ex.Message });
            }
        }

        protected override void Dispose(bool disposing)
        {
            if (disposing)
            {
                db.Dispose();
            }
            base.Dispose(disposing);
        }
    }
}
