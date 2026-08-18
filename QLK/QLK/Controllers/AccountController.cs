using QLK.Models;
using System;
using System.Linq;
using System.Web;
using System.Web.Mvc;
using System.Web.Security;
using TKELog.Models.ViewModels;
// ĐÃ XÓA: using TKELog.Models.ViewModels;

namespace QLK.Controllers
{
    public class AccountController : Controller
    {
        private DO_AN_QLKEntities db = new DO_AN_QLKEntities();

        // GET: Account/Login
        [HttpGet]
        public ActionResult Login(string returnUrl)
        {
            // Nếu đã đăng nhập rồi thì chuyển thẳng về trang Home
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

            var user = db.nguoi_dung.FirstOrDefault(u => u.ten_dang_nhap == model.TenDangNhap);

            if (user == null || !BCrypt.Net.BCrypt.Verify(model.MatKhau, user.mat_khau_ma_hoa))
            {
                ModelState.AddModelError("", "Tên đăng nhập hoặc mật khẩu không chính xác.");
                return View(model);
            }

            if (user.trang_thai_hoat_dong == false)
            {
                ModelState.AddModelError("", "Tài khoản bị khóa.");
                return View(model);
            }

            // TẠO TICKET GHI NHỚ ĐĂNG NHẬP CHUẨN (Nhúng Vai Trò vào Cookie)
            // Cấu trúc userData: "MaNguoiDung|HoTen|VaiTro"
            string userData = $"{user.ma_nguoi_dung}|{user.ho_ten}|{user.vai_tro}";

            var authTicket = new FormsAuthenticationTicket(
                1,                                  // Version
                user.ten_dang_nhap,                 // Tên đăng nhập
                DateTime.Now,                       // Thời gian tạo
                DateTime.Now.AddHours(8),           // Thời gian hết hạn (8 tiếng)
                model.GhiNho,                       // Có ghi nhớ không? (Remember Me)
                userData                            // Dữ liệu nhúng kèm
            );

            string encryptedTicket = FormsAuthentication.Encrypt(authTicket);
            var authCookie = new HttpCookie(FormsAuthentication.FormsCookieName, encryptedTicket)
            {
                HttpOnly = true,
                Expires = model.GhiNho ? authTicket.Expiration : DateTime.MinValue // Nếu Remember Me = true thì set hạn cho Cookie
            };
            Response.Cookies.Add(authCookie);

            // Đồng thời set Session dùng tạm cho phiên hiện tại
            Session["MaNguoiDung"] = user.ma_nguoi_dung;
            Session["HoTen"] = user.ho_ten;
            Session["VaiTro"] = user.vai_tro;

            return RedirectToLocal(returnUrl);
        }

        // Hàm hỗ trợ điều hướng an toàn
        private ActionResult RedirectToLocal(string returnUrl)
        {
            if (!string.IsNullOrEmpty(returnUrl) && Url.IsLocalUrl(returnUrl))
            {
                return Redirect(returnUrl);
            }
            // Mặc định chuyển hướng sang HomeController, Action Index (Trang chủ / Dashboard)
            return RedirectToAction("Index", "Home");
        }
        [HttpPost]
        [ValidateAntiForgeryToken]
        public ActionResult Logout()
        {
            // Xóa cookie xác thực
            FormsAuthentication.SignOut();
            // Xóa session hiện tại
            Session.Clear();
            Session.Abandon();

            return RedirectToAction("Login", "Account");
        }
        [HttpGet]
        [AllowAnonymous]
        public ActionResult ForgotPassword()
        {
            return View();
        }

        [HttpPost]
        [AllowAnonymous]
        [ValidateAntiForgeryToken]
        public ActionResult ForgotPassword(ForgotPasswordViewModel model)
        {
            if (!ModelState.IsValid)
            {
                return View(model);
            }

            // Tìm user theo Email
            var user = db.nguoi_dung.FirstOrDefault(u => u.email == model.Email);

            if (user != null && user.trang_thai_hoat_dong == true)
            {
                // 1. Sinh mật khẩu tạm thời ngẫu nhiên (Ví dụ: 8 ký tự)
                string matKhauTam = Guid.NewGuid().ToString().Substring(0, 8);

                // 2. Mã hóa BCrypt và cập nhật vào DB
                user.mat_khau_ma_hoa = BCrypt.Net.BCrypt.HashPassword(matKhauTam);
                user.ngay_cap_nhat = DateTime.Now;
                db.SaveChanges();

                // 3. Gửi Email chứa mật khẩu tạm (MOCK - Tích hợp SMTP thực tế sau)
                // SendEmail(user.email, "Phục hồi mật khẩu TKELog", $"Mật khẩu mới của bạn là: {matKhauTam}");

                TempData["SuccessMessage"] = "Mật khẩu mới đã được gửi đến email của bạn. Vui lòng kiểm tra hộp thư.";
                return RedirectToAction("Login");
            }

            // Dù không tìm thấy email, vẫn báo chung chung để tránh bị hacker dò quét email trong hệ thống
            TempData["SuccessMessage"] = "Nếu email hợp lệ, một hướng dẫn phục hồi đã được gửi đi.";
            return RedirectToAction("Login");
        }

        // ==========================================
        // TÍNH NĂNG 2: ĐỔI MẬT KHẨU
        // Yêu cầu: Phải đăng nhập mới được đổi
        // ==========================================
        [HttpGet]
        [Authorize]
        public ActionResult ChangePassword()
        {
            return View();
        }

        [HttpPost]
        [Authorize]
        [ValidateAntiForgeryToken]
        public ActionResult ChangePassword(ChangePasswordViewModel model)
        {
            if (!ModelState.IsValid)
            {
                return View(model);
            }

            if (model.MatKhauMoi != model.XacNhanMatKhau)
            {
                ModelState.AddModelError("", "Mật khẩu xác nhận không khớp.");
                return View(model);
            }

            // Lấy Mã người dùng từ Session đã lưu lúc Login
            int maNguoiDung = (int)Session["MaNguoiDung"];
            var user = db.nguoi_dung.Find(maNguoiDung);

            if (user == null)
            {
                return RedirectToAction("Login");
            }

            // Kiểm tra mật khẩu cũ
            if (!BCrypt.Net.BCrypt.Verify(model.MatKhauCu, user.mat_khau_ma_hoa))
            {
                ModelState.AddModelError("", "Mật khẩu cũ không chính xác.");
                return View(model);
            }

            // Mã hóa mật khẩu mới và lưu DB
            user.mat_khau_ma_hoa = BCrypt.Net.BCrypt.HashPassword(model.MatKhauMoi);
            user.ngay_cap_nhat = DateTime.Now;
            db.SaveChanges();

            // Đổi mật khẩu thành công -> Xóa phiên đăng nhập bắt đăng nhập lại để đảm bảo an toàn
            FormsAuthentication.SignOut();
            Session.Clear();

            TempData["SuccessMessage"] = "Đổi mật khẩu thành công. Vui lòng đăng nhập lại.";
            return RedirectToAction("Login");
        }
    }
}