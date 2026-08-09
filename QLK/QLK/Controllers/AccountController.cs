using QLK.Models; // Namespace chứa DoAn.edmx và AccountViewModels.cs
using System;
using System.Linq;
using System.Web;
using System.Web.Mvc;
using System.Web.Security;
using TKELog.Models.ViewModels;

namespace QLK.Controllers
{
    public class AccountController : Controller
    {
        // Khởi tạo DbContext từ DoAn.edmx (DoAnEntities hoặc DO_AN_QLKEntities)
        private DO_AN_QLKEntities db = new DO_AN_QLKEntities();

        // GET: Account/Login
        [HttpGet]
        public ActionResult Login(string returnUrl)
        {
            if (User.Identity.IsAuthenticated)
            {
                return RedirectToLocal(returnUrl);
            }
            ViewBag.ReturnUrl = returnUrl;
            return View();
        }

        // POST: Account/Login
        [HttpPost]
        [ValidateAntiForgeryToken]
        public ActionResult Login(LoginViewModel model, string returnUrl)
        {
            if (!ModelState.IsValid)
            {
                return View(model);
            }

            // Tìm người dùng trong DB theo ten_dang_nhap
            var user = db.nguoi_dung.FirstOrDefault(u => u.ten_dang_nhap == model.TenDangNhap);

            // Xác thực mật khẩu mã hóa BCrypt
            if (user == null || !BCrypt.Net.BCrypt.Verify(model.MatKhau, user.mat_khau_ma_hoa))
            {
                ModelState.AddModelError("", "Tên đăng nhập hoặc mật khẩu không chính xác.");
                return View(model);
            }

            // Kiểm tra trạng thái tài khoản
            if (user.trang_thai_hoat_dong == false)
            {
                ModelState.AddModelError("", "Tài khoản của bạn đã bị khóa.");
                return View(model);
            }

            // Cấu hình Cookie Đăng nhập FormsAuthentication & Session
            FormsAuthentication.SetAuthCookie(user.ten_dang_nhap, model.GhiNho);
            Session["MaNguoiDung"] = user.ma_nguoi_dung;
            Session["HoTen"] = user.ho_ten;
            Session["VaiTro"] = user.vai_tro;

            return RedirectToLocal(returnUrl);
        }

        // GET: Account/Register
        [HttpGet]
        public ActionResult Register()
        {
            return View();
        }

        // POST: Account/Register
        [HttpPost]
        [ValidateAntiForgeryToken]
        public ActionResult Register(RegisterViewModel model)
        {
            if (!ModelState.IsValid)
            {
                return View(model);
            }

            // Kiểm tra tên đăng nhập tồn tại
            if (db.nguoi_dung.Any(u => u.ten_dang_nhap == model.TenDangNhap))
            {
                ModelState.AddModelError("TenDangNhap", "Tên đăng nhập này đã được sử dụng.");
                return View(model);
            }

            // Khởi tạo đối tượng Entity nguoi_dung
            var newUser = new nguoi_dung
            {
                ten_dang_nhap = model.TenDangNhap,
                mat_khau_ma_hoa = BCrypt.Net.BCrypt.HashPassword(model.MatKhau),
                ho_ten = model.HoTen,
                vai_tro = string.IsNullOrEmpty(model.VaiTro) ? "BAN_HANG" : model.VaiTro,
                trang_thai_hoat_dong = true,
                ngay_tao = DateTime.Now,
                ngay_cap_nhat = DateTime.Now
            };

            db.nguoi_dung.Add(newUser);
            db.SaveChanges();

            TempData["SuccessMessage"] = "Đăng ký tài khoản thành công! Vui lòng đăng nhập.";
            return RedirectToAction("Login");
        }

        // POST: Account/Logout
        [HttpPost]
        [ValidateAntiForgeryToken]
        public ActionResult Logout()
        {
            FormsAuthentication.SignOut();
            Session.Clear();
            Session.Abandon();
            return RedirectToAction("Login", "Account");
        }

        private ActionResult RedirectToLocal(string returnUrl)
        {
            if (!string.IsNullOrEmpty(returnUrl) && Url.IsLocalUrl(returnUrl))
            {
                return Redirect(returnUrl);
            }
            return RedirectToAction("Index", "Home");
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