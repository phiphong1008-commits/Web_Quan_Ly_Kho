using System;
using System.Data.Entity;
using System.Linq;
using System.Net;
using System.Web.Mvc;
using QLK.Models;

namespace QLK.Controllers
{
    public class UserPayload
    {
        public int MaNguoiDung { get; set; }
        public string TenDangNhap { get; set; }
        public string HoTen { get; set; }
        public string VaiTro { get; set; }
        public bool TrangThaiHoatDong { get; set; }
        public string MatKhau { get; set; }
        public string MatKhauMoi { get; set; }
    }

    [ChiChoPhep("CHU", "QUAN_LY")]
    public class NguoiDungController : BaseController
    {
        private DO_AN_QLKEntities db = new DO_AN_QLKEntities();

        private bool NguoiHienTaiLaChu() => VaiTroHienTai == "CHU";

        public ActionResult Index()
        {
            var dsNguoiDung = db.nguoi_dung.OrderByDescending(u => u.ngay_tao).ToList();
            return View(dsNguoiDung);
        }

        public ActionResult Details(int? id)
        {
            if (id == null) return new HttpStatusCodeResult(HttpStatusCode.BadRequest);
            nguoi_dung nguoiDung = db.nguoi_dung.Find(id);
            if (nguoiDung == null) return HttpNotFound();
            return View(nguoiDung);
        }

        [HttpPost]
        public JsonResult Create(UserPayload payload)
        {
            if (string.IsNullOrWhiteSpace(payload.MatKhau) || payload.MatKhau.Length < 6)
                return Json(new { success = false, message = "Mật khẩu phải từ 6 ký tự trở lên." });

            if (db.nguoi_dung.Any(u => u.ten_dang_nhap == payload.TenDangNhap))
                return Json(new { success = false, message = "Tên đăng nhập đã tồn tại." });

            if (payload.VaiTro == "CHU" && !NguoiHienTaiLaChu())
                return Json(new { success = false, message = "Chỉ Chủ hệ thống mới tạo được tài khoản Chủ." });

            var newUser = new nguoi_dung
            {
                ten_dang_nhap = payload.TenDangNhap,
                ho_ten = payload.HoTen,
                vai_tro = payload.VaiTro,
                trang_thai_hoat_dong = payload.TrangThaiHoatDong,
                mat_khau_ma_hoa = BCrypt.Net.BCrypt.HashPassword(payload.MatKhau),
                ngay_tao = DateTime.Now,
                ngay_cap_nhat = DateTime.Now
            };

            db.nguoi_dung.Add(newUser);
            db.SaveChanges();

            return Json(new { success = true, message = "Thêm thành công!" });
        }

        [HttpPost]
        public JsonResult Edit(UserPayload payload)
        {
            var userInDb = db.nguoi_dung.Find(payload.MaNguoiDung);
            if (userInDb == null) return Json(new { success = false, message = "Không tìm thấy tài khoản." });

            bool dangDoiThanhChu = payload.VaiTro == "CHU" && userInDb.vai_tro != "CHU";
            bool dangSuaTaiKhoanChu = userInDb.vai_tro == "CHU";
            if ((dangDoiThanhChu || dangSuaTaiKhoanChu) && !NguoiHienTaiLaChu())
                return Json(new { success = false, message = "Không đủ quyền cấp/sửa tài khoản Chủ." });

            userInDb.ho_ten = payload.HoTen;
            userInDb.vai_tro = payload.VaiTro;
            userInDb.trang_thai_hoat_dong = payload.TrangThaiHoatDong;
            userInDb.ngay_cap_nhat = DateTime.Now;

            if (!string.IsNullOrWhiteSpace(payload.MatKhauMoi))
            {
                if (payload.MatKhauMoi.Length < 6) return Json(new { success = false, message = "Mật khẩu mới phải >= 6 ký tự." });
                userInDb.mat_khau_ma_hoa = BCrypt.Net.BCrypt.HashPassword(payload.MatKhauMoi);
            }

            db.Entry(userInDb).State = EntityState.Modified;
            db.SaveChanges();

            return Json(new { success = true, message = "Cập nhật thành công!" });
        }

        [HttpPost]
        public JsonResult Delete(int id)
        {
            var nguoiDung = db.nguoi_dung.Find(id);
            if (nguoiDung == null) return Json(new { success = false, message = "Không tìm thấy!" });

            if (MaNguoiDungHienTai == id)
                return Json(new { success = false, message = "Không thể khóa tài khoản đang đăng nhập!" });

            if (nguoiDung.vai_tro == "CHU" && db.nguoi_dung.Count(u => u.vai_tro == "CHU" && u.ma_nguoi_dung != id) == 0)
                return Json(new { success = false, message = "Đây là tài khoản Chủ duy nhất, không thể khóa!" });

            nguoiDung.trang_thai_hoat_dong = false;
            nguoiDung.ngay_cap_nhat = DateTime.Now;

            db.Entry(nguoiDung).State = EntityState.Modified;
            db.SaveChanges();

            return Json(new { success = true, message = "Khóa tài khoản thành công!" });
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

        [HttpGet]
        public JsonResult GetById(int id)
        {
            var user = db.nguoi_dung.Find(id);
            if (user == null)
            {
                return Json(new { success = false, message = "Không tìm thấy người dùng!" }, JsonRequestBehavior.AllowGet);
            }

            var data = new
            {
                maNguoiDung = user.ma_nguoi_dung,
                tenDangNhap = user.ten_dang_nhap,
                hoTen = user.ho_ten,
                vaiTro = user.vai_tro,
                trangThaiHoatDong = user.trang_thai_hoat_dong
            };

            return Json(new { success = true, data = data }, JsonRequestBehavior.AllowGet);
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