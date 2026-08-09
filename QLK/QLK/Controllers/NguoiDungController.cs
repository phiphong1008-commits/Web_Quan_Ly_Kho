using System;
using System.Collections.Generic;
using System.Data;
using System.Data.Entity;
using System.Linq;
using System.Net;
using System.Web;
using System.Web.Mvc;
using QLK.Models;

namespace QLK.Controllers
{
    public class NguoiDungController : Controller
    {
        private DO_AN_QLKEntities db = new DO_AN_QLKEntities();

        // Kiểm tra quyền Quản trị (Chỉ CHU hoặc QUAN_LY mới được truy cập quản lý người dùng)
        private bool KiemTraQuyenQuanTri()
        {
            var vaiTro = Session["VaiTro"] as string;
            return vaiTro == "CHU" || vaiTro == "QUAN_LY";
        }

        // GET: NguoiDung
        public ActionResult Index()
        {
            if (!KiemTraQuyenQuanTri())
            {
                TempData["ErrorMessage"] = "Bạn không có quyền truy cập vào chức năng quản lý tài khoản.";
                return RedirectToAction("Index", "Home");
            }

            var dsNguoiDung = db.nguoi_dung.OrderByDescending(u => u.ngay_tao).ToList();
            return View(dsNguoiDung);
        }

        // GET: NguoiDung/Details/5
        public ActionResult Details(int? id)
        {
            if (!KiemTraQuyenQuanTri())
                return RedirectToAction("Index", "Home");

            if (id == null)
            {
                return new HttpStatusCodeResult(HttpStatusCode.BadRequest);
            }

            nguoi_dung nguoiDung = db.nguoi_dung.Find(id);
            if (nguoiDung == null)
            {
                return HttpNotFound();
            }

            return View(nguoiDung);
        }

        // GET: NguoiDung/Create
        public ActionResult Create()
        {
            if (!KiemTraQuyenQuanTri())
                return RedirectToAction("Index", "Home");

            ViewBag.DanhSachVaiTro = SelectListVaiTro();
            return View();
        }

        // POST: NguoiDung/Create
        [HttpPost]
        [ValidateAntiForgeryToken]
        public ActionResult Create([Bind(Include = "ten_dang_nhap,ho_ten,vai_tro,trang_thai_hoat_dong")] nguoi_dung nguoiDung, string mat_khau)
        {
            if (!KiemTraQuyenQuanTri())
                return RedirectToAction("Index", "Home");

            if (string.IsNullOrWhiteSpace(mat_khau) || mat_khau.Length < 6)
            {
                ModelState.AddModelError("", "Mật khẩu không được để trống và phải từ 6 ký tự trở lên.");
            }

            if (db.nguoi_dung.Any(u => u.ten_dang_nhap == nguoiDung.ten_dang_nhap))
            {
                ModelState.AddModelError("ten_dang_nhap", "Tên đăng nhập này đã tồn tại.");
            }

            if (ModelState.IsValid)
            {
                nguoiDung.mat_khau_ma_hoa = BCrypt.Net.BCrypt.HashPassword(mat_khau);
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
            if (!KiemTraQuyenQuanTri())
                return RedirectToAction("Index", "Home");

            if (id == null)
            {
                return new HttpStatusCodeResult(HttpStatusCode.BadRequest);
            }

            nguoi_dung nguoiDung = db.nguoi_dung.Find(id);
            if (nguoiDung == null)
            {
                return HttpNotFound();
            }

            ViewBag.DanhSachVaiTro = SelectListVaiTro(nguoiDung.vai_tro);
            return View(nguoiDung);
        }

        // POST: NguoiDung/Edit/5
        [HttpPost]
        [ValidateAntiForgeryToken]
        public ActionResult Edit([Bind(Include = "ma_nguoi_dung,ten_dang_nhap,ho_ten,vai_tro,trang_thai_hoat_dong,ngay_tao")] nguoi_dung nguoiDung, string mat_khau_moi)
        {
            if (!KiemTraQuyenQuanTri())
                return RedirectToAction("Index", "Home");

            if (ModelState.IsValid)
            {
                var userInDb = db.nguoi_dung.Find(nguoiDung.ma_nguoi_dung);
                if (userInDb == null)
                {
                    return HttpNotFound();
                }

                // Cập nhật thông tin cá nhân & vai trò
                userInDb.ho_ten = nguoiDung.ho_ten;
                userInDb.vai_tro = nguoiDung.vai_tro;
                userInDb.trang_thai_hoat_dong = nguoiDung.trang_thai_hoat_dong;
                userInDb.ngay_cap_nhat = DateTime.Now;

                // Đổi mật khẩu nếu người dùng có nhập mật khẩu mới
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

        // GET: NguoiDung/Delete/5
        public ActionResult Delete(int? id)
        {
            if (!KiemTraQuyenQuanTri())
                return RedirectToAction("Index", "Home");

            if (id == null)
            {
                return new HttpStatusCodeResult(HttpStatusCode.BadRequest);
            }

            nguoi_dung nguoiDung = db.nguoi_dung.Find(id);
            if (nguoiDung == null)
            {
                return HttpNotFound();
            }

            return View(nguoiDung);
        }

        // POST: NguoiDung/Delete/5
        [HttpPost, ActionName("Delete")]
        [ValidateAntiForgeryToken]
        public ActionResult DeleteConfirmed(int id)
        {
            if (!KiemTraQuyenQuanTri())
                return RedirectToAction("Index", "Home");

            nguoi_dung nguoiDung = db.nguoi_dung.Find(id);
            if (nguoiDung == null)
            {
                return HttpNotFound();
            }

            // Ràng buộc nghiệp vụ: Không cho phép tự xóa chính mình
            var currentUserId = Session["MaNguoiDung"] as int?;
            if (currentUserId.HasValue && currentUserId.Value == id)
            {
                TempData["ErrorMessage"] = "Bạn không thể xóa tài khoản đang đăng nhập!";
                return RedirectToAction("Index");
            }

            db.nguoi_dung.Remove(nguoiDung);
            db.SaveChanges();

            TempData["SuccessMessage"] = "Xóa người dùng thành công!";
            return RedirectToAction("Index");
        }

        // Hàm hỗ trợ tạo DropDownList danh sách Vai Trò đúng chuẩn CHECK Constraint của CSDL
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