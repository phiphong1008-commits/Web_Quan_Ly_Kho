using QLK.Models;
using QLK.Models.ViewModels;
using System;
using System.Configuration;
using System.Linq;
using System.Net;
using System.Net.Mail;
using System.Web;
using System.Web.Mvc;
using System.Web.Security;

// ĐÃ XÓA: using QLK.Models.ViewModels;

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

            // Kiểm tra tính hợp lệ của Tên đăng nhập và Email
            var user = db.nguoi_dung.FirstOrDefault(u => u.ten_dang_nhap == model.TenDangNhap && u.email == model.Email);

            if (user != null && user.trang_thai_hoat_dong == true)
            {
                Random random = new Random();
                string otpCode = random.Next(100000, 999999).ToString();

                Session["ResetOTP"] = otpCode;
                Session["ResetUserID"] = user.ma_nguoi_dung;
                Session["OTPExpiry"] = DateTime.Now.AddMinutes(5);

                // SỬA: kiểm tra kết quả gửi mail, không còn giả định luôn thành công
                bool guiThanhCong = SendEmailOTP(user.email, otpCode);
                if (!guiThanhCong)
                {
                    ModelState.AddModelError("", "Không gửi được email OTP. Vui lòng thử lại sau hoặc liên hệ quản trị viên.");
                    return View(model);
                }

                return RedirectToAction("VerifyOTP");
            }

            ModelState.AddModelError("", "Tên đăng nhập hoặc Email không chính xác/không tồn tại.");
            return View(model);
        }

        // ==========================================
        // BƯỚC 2: XÁC THỰC MÃ OTP
        // ==========================================
        [HttpGet]
        [AllowAnonymous]
        public ActionResult VerifyOTP()
        {
            if (Session["ResetOTP"] == null) return RedirectToAction("Login");
            return View();
        }

        [HttpPost]
        [AllowAnonymous]
        [ValidateAntiForgeryToken]
        public ActionResult VerifyOTP(string otpCode)
        {
            if (Session["ResetOTP"] != null && Session["OTPExpiry"] != null)
            {
                DateTime expiry = (DateTime)Session["OTPExpiry"];
                if (DateTime.Now > expiry)
                {
                    ModelState.AddModelError("", "Mã OTP đã hết hạn. Vui lòng yêu cầu lại.");
                    return View();
                }

                if (Session["ResetOTP"].ToString() == otpCode)
                {
                    // OTP hợp lệ, đánh dấu session đã xác thực để cho phép đổi mật khẩu
                    Session["OTPVerified"] = true;
                    return RedirectToAction("ResetPassword");
                }
            }

            ModelState.AddModelError("", "Mã xác nhận không hợp lệ.");
            return View();
        }

        // ==========================================
        // BƯỚC 3: ĐẶT LẠI MẬT KHẨU MỚI
        // ==========================================
        [HttpGet]
        [AllowAnonymous]
        public ActionResult ResetPassword()
        {
            // Chỉ cho phép truy cập khi đã qua bước VerifyOTP
            if (Session["OTPVerified"] == null || (bool)Session["OTPVerified"] == false)
            {
                return RedirectToAction("Login");
            }
            return View();
        }

        [HttpPost]
        [AllowAnonymous]
        [ValidateAntiForgeryToken]
        public ActionResult ResetPassword(ResetPasswordViewModel model)
        {
            // 1. Kiểm tra tính hợp lệ của Model nhập vào
            if (!ModelState.IsValid)
            {
                return View(model);
            }

            // 2. Chặn việc truy cập thẳng vào link khi chưa qua bước OTP
            if (Session["ResetUserID"] == null || Session["OTPVerified"] == null || (bool)Session["OTPVerified"] == false)
            {
                TempData["ErrorMessage"] = "Phiên làm việc đã hết hạn hoặc không hợp lệ. Vui lòng thao tác lại từ đầu.";
                return RedirectToAction("ForgotPassword", "Account");
            }

            try
            {
                int userId = (int)Session["ResetUserID"];

                // 3. Dùng Find() để lấy và để Entity Framework tự động Tracking sự thay đổi
                var user = db.nguoi_dung.Find(userId);

                if (user != null)
                {
                    // 4. Chỉ gán thông tin mới, KHÔNG dùng lệnh db.Entry().State = Modified
                    user.mat_khau_ma_hoa = BCrypt.Net.BCrypt.HashPassword(model.MatKhauMoi);
                    user.ngay_cap_nhat = DateTime.Now;

                    // 5. Lưu vào CSDL
                    db.SaveChanges();

                    // 6. Xóa dọn dẹp toàn bộ Session của luồng quên mật khẩu
                    Session.Remove("ResetOTP");
                    Session.Remove("ResetUserID");
                    Session.Remove("OTPExpiry");
                    Session.Remove("OTPVerified");

                    // 7. Chuyển hướng về trang Đăng nhập thành công
                    TempData["SuccessMessage"] = "Khôi phục mật khẩu thành công. Vui lòng đăng nhập lại bằng mật khẩu mới.";
                    return RedirectToAction("Login", "Account");
                }
                else
                {
                    ModelState.AddModelError("", "Không tìm thấy dữ liệu người dùng trong hệ thống.");
                    return View(model);
                }
            }
            catch (System.Data.Entity.Validation.DbEntityValidationException ex)
            {
                // 8. BẮT LỖI SÂU: Hiển thị đích danh cột CSDL nào ngăn cản việc lưu
                foreach (var validationErrors in ex.EntityValidationErrors)
                {
                    foreach (var validationError in validationErrors.ValidationErrors)
                    {
                        ModelState.AddModelError("", $"Lỗi ràng buộc CSDL: {validationError.PropertyName} - {validationError.ErrorMessage}");
                    }
                }
                return View(model);
            }
            catch (Exception ex)
            {
                // Bắt các lỗi chung (như rớt kết nối DB)
                ModelState.AddModelError("", "Lỗi hệ thống khi lưu: " + ex.Message);
                return View(model);
            }
        }

        // Hàm hỗ trợ gửi mail (Cần điền thông tin SMTP thực tế của hệ thống)
        private bool SendEmailOTP(string toEmail, string otpCode)
        {
            try
            {
                // Lấy từ Web.config thay vì hardcode - tránh lộ mật khẩu khi đẩy code lên Git
                string smtpEmail = ConfigurationManager.AppSettings["SmtpEmail"];
                string smtpAppPassword = ConfigurationManager.AppSettings["SmtpAppPassword"];

                // fromAddress PHẢI là đúng Gmail đã tạo App Password ở bước trên -
                // không được để địa chỉ khác (ví dụ no-reply@tkelog.com) vì Gmail
                // sẽ từ chối xác thực SMTP nếu From không khớp tài khoản đăng nhập.
                var fromAddress = new MailAddress(smtpEmail, "QLK - Hệ thống quản lý kho");
                var toAddress = new MailAddress(toEmail);

                string subject = "Mã xác nhận khôi phục mật khẩu";
                string body = $"Mã OTP của bạn là: {otpCode}. Mã có hiệu lực trong 5 phút. Vui lòng không chia sẻ cho bất kỳ ai.";

                var smtp = new SmtpClient
                {
                    Host = "smtp.gmail.com",
                    Port = 587,
                    EnableSsl = true,
                    DeliveryMethod = SmtpDeliveryMethod.Network,
                    UseDefaultCredentials = false,
                    Credentials = new NetworkCredential(smtpEmail, smtpAppPassword)
                };

                using (var message = new MailMessage(fromAddress, toAddress)
                {
                    Subject = subject,
                    Body = body
                })
                {
                    smtp.Send(message);
                }

                return true; // gửi thành công
            }
            catch (Exception ex)
            {
                // KHÔNG được để trống catch như bản cũ - ít nhất ghi ra log/Trace để
                // biết chính xác vì sao gửi thất bại lúc debug (sai mật khẩu? sai host?...)
                System.Diagnostics.Trace.TraceError("Lỗi gửi email OTP: " + ex.Message);
                return false; // gửi thất bại
            }
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