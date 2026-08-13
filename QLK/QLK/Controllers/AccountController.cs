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