using System;
using System.Data.Entity;
using System.Linq;
using System.Net;
using System.Web.Mvc;
using QLK.Models;

namespace QLK.Controllers
{
    // Thay "KiemTraQuyenQuanTri()" lặp lại 7 lần bằng 1 attribute áp cho
    // TOÀN BỘ controller - mọi action bên dưới đều tự động chỉ cho CHU/QUAN_LY vào,
    // action mới thêm sau này cũng tự động được bảo vệ mà không cần nhớ dán lại.
    [ChiChoPhep("CHU", "QUAN_LY")]
    public class NguoiDungController : BaseController
    {
        private DO_AN_QLKEntities db = new DO_AN_QLKEntities();

        // Người đang đăng nhập có phải CHU không - dùng để chặn leo thang đặc quyền.
        // Đây là kiểm tra RIÊNG của controller này (không phải "vào được hay không" mà
        // là "được làm hành động cụ thể này hay không"), nên vẫn giữ tại đây, không đưa
        // lên attribute/BaseController vì attribute chỉ xử lý được rule chung, cố định.
        private bool NguoiHienTaiLaChu() => VaiTroHienTai == "CHU";

        // GET: NguoiDung
        public ActionResult Index()
        {
            var dsNguoiDung = db.nguoi_dung.OrderByDescending(u => u.ngay_tao).ToList();
            return View(dsNguoiDung);
        }

        // GET: NguoiDung/Details/5
        public ActionResult Details(int? id)
        {
            if (id == null)
                return new HttpStatusCodeResult(HttpStatusCode.BadRequest);

            nguoi_dung nguoiDung = db.nguoi_dung.Find(id);
            if (nguoiDung == null)
                return HttpNotFound();

            return View(nguoiDung);
        }

        // GET: NguoiDung/Create
        public ActionResult Create()
        {
            ViewBag.DanhSachVaiTro = SelectListVaiTro();
            return View();
        }

        // POST: NguoiDung/Create
        [HttpPost]
        [ValidateAntiForgeryToken]
        public ActionResult Create([Bind(Include = "ten_dang_nhap,ho_ten,vai_tro,trang_thai_hoat_dong")] nguoi_dung nguoiDung, string mat_khau)
        {
            if (string.IsNullOrWhiteSpace(mat_khau) || mat_khau.Length < 6)
            {
                ModelState.AddModelError("", "Mật khẩu không được để trống và phải từ 6 ký tự trở lên.");
            }

            if (db.nguoi_dung.Any(u => u.ten_dang_nhap == nguoiDung.ten_dang_nhap))
            {
                ModelState.AddModelError("ten_dang_nhap", "Tên đăng nhập này đã tồn tại.");
            }

            // Chặn leo thang đặc quyền: chỉ CHU mới được tạo tài khoản CHU khác
            if (nguoiDung.vai_tro == "CHU" && !NguoiHienTaiLaChu())
            {
                ModelState.AddModelError("vai_tro", "Chỉ có Chủ hệ thống mới được tạo tài khoản cấp Chủ.");
            }

            if (ModelState.IsValid)
            {
                nguoiDung.mat_khau_ma_hoa = BCrypt.Net.BCrypt.HashPassword(mat_khau);

                // EF không tự áp DEFAULT của SQL khi Add() - set tường minh, tránh lưu NULL
                nguoiDung.trang_thai_hoat_dong = nguoiDung.trang_thai_hoat_dong ?? true;

                nguoiDung.ngay_tao = DateTime.Now;
                nguoiDung.ngay_cap_nhat = DateTime.Now;

                db.nguoi_dung.Add(nguoiDung);
                db.SaveChanges();

                TempData["SuccessMessage"] = "Thêm người dùng mới thành công!";
                return RedirectToAction("Index");
            }

            ViewBag.DanhSachVaiTro = SelectListVaiTro(nguoiDung.vai_tro);
            return View(nguoiDung);
        }

        // GET: NguoiDung/Edit/5
        public ActionResult Edit(int? id)
        {
            if (id == null)
                return new HttpStatusCodeResult(HttpStatusCode.BadRequest);

            nguoi_dung nguoiDung = db.nguoi_dung.Find(id);
            if (nguoiDung == null)
                return HttpNotFound();

            ViewBag.DanhSachVaiTro = SelectListVaiTro(nguoiDung.vai_tro);
            return View(nguoiDung);
        }

        // POST: NguoiDung/Edit/5
        [HttpPost]
        [ValidateAntiForgeryToken]
        public ActionResult Edit([Bind(Include = "ma_nguoi_dung,ten_dang_nhap,ho_ten,vai_tro,trang_thai_hoat_dong,ngay_tao")] nguoi_dung nguoiDung, string mat_khau_moi)
        {
            var userInDb = db.nguoi_dung.Find(nguoiDung.ma_nguoi_dung);
            if (userInDb == null)
                return HttpNotFound();

            // Chặn leo thang đặc quyền: chỉ CHU mới được nâng ai đó lên CHU,
            // hoặc sửa thông tin của 1 tài khoản CHU đang có
            bool dangDoiThanhChu = nguoiDung.vai_tro == "CHU" && userInDb.vai_tro != "CHU";
            bool dangSuaTaiKhoanChu = userInDb.vai_tro == "CHU";
            if ((dangDoiThanhChu || dangSuaTaiKhoanChu) && !NguoiHienTaiLaChu())
            {
                ModelState.AddModelError("vai_tro", "Chỉ có Chủ hệ thống mới được cấp/sửa quyền Chủ.");
            }

            // Không cho hạ cấp CHU duy nhất còn lại
            if (userInDb.vai_tro == "CHU" && nguoiDung.vai_tro != "CHU")
            {
                int soLuongChuConLai = db.nguoi_dung.Count(u => u.vai_tro == "CHU" && u.ma_nguoi_dung != userInDb.ma_nguoi_dung);
                if (soLuongChuConLai == 0)
                {
                    ModelState.AddModelError("vai_tro", "Không thể hạ cấp - đây là tài khoản Chủ hệ thống duy nhất còn lại.");
                }
            }

            if (ModelState.IsValid)
            {
                userInDb.ho_ten = nguoiDung.ho_ten;
                userInDb.vai_tro = nguoiDung.vai_tro;
                userInDb.trang_thai_hoat_dong = nguoiDung.trang_thai_hoat_dong ?? true;
                userInDb.ngay_cap_nhat = DateTime.Now;

                if (!string.IsNullOrWhiteSpace(mat_khau_moi))
                {
                    if (mat_khau_moi.Length < 6)
                    {
                        ModelState.AddModelError("", "Mật khẩu mới phải có ít nhất 6 ký tự.");
                        ViewBag.DanhSachVaiTro = SelectListVaiTro(nguoiDung.vai_tro);
                        return View(nguoiDung);
                    }
                    userInDb.mat_khau_ma_hoa = BCrypt.Net.BCrypt.HashPassword(mat_khau_moi);
                }

                db.Entry(userInDb).State = EntityState.Modified;
                db.SaveChanges();

                TempData["SuccessMessage"] = "Cập nhật thông tin người dùng thành công!";
                return RedirectToAction("Index");
            }

            ViewBag.DanhSachVaiTro = SelectListVaiTro(nguoiDung.vai_tro);
            return View(nguoiDung);
        }

        // GET: NguoiDung/Delete/5  (thực chất là màn hình xác nhận KHÓA tài khoản)
        public ActionResult Delete(int? id)
        {
            if (id == null)
                return new HttpStatusCodeResult(HttpStatusCode.BadRequest);

            nguoi_dung nguoiDung = db.nguoi_dung.Find(id);
            if (nguoiDung == null)
                return HttpNotFound();

            return View(nguoiDung);
        }

        // POST: NguoiDung/Delete/5
        // Soft-delete: khóa tài khoản (trang_thai_hoat_dong = false) thay vì xóa cứng,
        // vì nguoi_dung bị nhiều bảng khác tham chiếu (lịch sử đơn hàng, chuyến giao hàng...)
        [HttpPost, ActionName("Delete")]
        [ValidateAntiForgeryToken]
        public ActionResult DeleteConfirmed(int id)
        {
            nguoi_dung nguoiDung = db.nguoi_dung.Find(id);
            if (nguoiDung == null)
                return HttpNotFound();

            if (MaNguoiDungHienTai == id)
            {
                TempData["ErrorMessage"] = "Bạn không thể khóa tài khoản đang đăng nhập!";
                return RedirectToAction("Index");
            }

            if (nguoiDung.vai_tro == "CHU")
            {
                int soLuongChuConLai = db.nguoi_dung.Count(u => u.vai_tro == "CHU" && u.ma_nguoi_dung != id);
                if (soLuongChuConLai == 0)
                {
                    TempData["ErrorMessage"] = "Không thể khóa - đây là tài khoản Chủ hệ thống duy nhất còn lại.";
                    return RedirectToAction("Index");
                }
            }

            nguoiDung.trang_thai_hoat_dong = false;
            nguoiDung.ngay_cap_nhat = DateTime.Now;
            db.Entry(nguoiDung).State = EntityState.Modified;
            db.SaveChanges();

            TempData["SuccessMessage"] = "Đã khóa tài khoản người dùng!";
            return RedirectToAction("Index");
        }

        private SelectList SelectListVaiTro(string selectedValue = "BAN_HANG")
        {
            var dsVaiTro = new[]
            {
                new { Value = "CHU", Text = "Chủ hệ thống (Full Control)" },
                new { Value = "QUAN_LY", Text = "Quản lý kho / đội xe" },
                new { Value = "NHAN_VIEN_KHO", Text = "Nhân viên kho" },
                new { Value = "BAN_HANG", Text = "Nhân viên bán hàng" },
                new { Value = "TAI_XE", Text = "Tài xế giao hàng" }
            };

            return new SelectList(dsVaiTro, "Value", "Text", selectedValue);
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