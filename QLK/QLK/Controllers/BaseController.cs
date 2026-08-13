using System.Web.Mvc;

namespace QLK.Controllers
{
    /// <summary>
    /// Mọi Controller cần bắt buộc đăng nhập thì kế thừa từ đây thay vì
    /// kế thừa trực tiếp từ Controller. Chỉ cần đổi:
    ///     public class XxxController : Controller
    /// thành:
    ///     public class XxxController : BaseController
    /// KHÔNG cần gọi thêm bất kỳ dòng nào khác trong XxxController - MVC tự
    /// động gọi OnActionExecuting() dưới đây trước MỌI action của XxxController.
    /// </summary>
    public class BaseController : Controller
    {
        protected override void OnActionExecuting(ActionExecutingContext filterContext)
        {
            if (Session["MaNguoiDung"] == null)
            {
                // Chưa đăng nhập -> chặn lại, chuyển hướng về trang đăng nhập,
                // đồng thời nhớ lại URL đang định vào để quay lại sau khi đăng nhập xong.
                var returnUrl = filterContext.HttpContext.Request.Url?.PathAndQuery;
                filterContext.Result = new RedirectToRouteResult(
                    new System.Web.Routing.RouteValueDictionary
                    {
                        { "controller", "Account" },
                        { "action", "Login" },
                        { "returnUrl", returnUrl }
                    });
                return; // KHÔNG gọi base - action gốc sẽ không được chạy nữa
            }

            base.OnActionExecuting(filterContext);
        }

        // Tiện ích dùng chung: lấy nhanh mã người dùng đang đăng nhập,
        // dùng trong các action như DonHangController.Tao/Huy thay vì
        // ép kiểu (int)Session["MaNguoiDung"] trực tiếp (dễ crash nếu null).
        protected int MaNguoiDungHienTai => (int)Session["MaNguoiDung"];

        protected string VaiTroHienTai => Session["VaiTro"] as string;
    }
}