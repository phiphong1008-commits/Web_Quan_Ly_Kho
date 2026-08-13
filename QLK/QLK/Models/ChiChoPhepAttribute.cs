using System.Linq;
using System.Web.Mvc;

namespace QLK.Controllers
{
    /// <summary>
    /// Gắn attribute này lên 1 action hoặc cả 1 Controller (class) để giới hạn
    /// chỉ những vai trò được liệt kê mới truy cập được.
    /// Ví dụ:
    ///     [ChiChoPhep("CHU", "QUAN_LY")]
    ///     public class NguoiDungController : BaseController
    ///
    /// LƯU Ý VỀ THỨ TỰ CHẠY: Attribute gắn ở CLASS chạy TRƯỚC
    /// BaseController.OnActionExecuting (MVC gọi filter theo Scope: Controller
    /// -> ... -> Last, và OnActionExecuting override trong Controller luôn có
    /// Scope = Last). Vì vậy attribute này TỰ kiểm tra luôn cả việc đã đăng
    /// nhập hay chưa (không dựa vào BaseController chạy trước) để tránh hiện
    /// nhầm thông báo "không đủ quyền" cho người còn CHƯA đăng nhập.
    /// </summary>
    public class ChiChoPhepAttribute : ActionFilterAttribute
    {
        private readonly string[] _vaiTroChoPhep;

        public ChiChoPhepAttribute(params string[] vaiTroChoPhep)
        {
            _vaiTroChoPhep = vaiTroChoPhep;
        }

        public override void OnActionExecuting(ActionExecutingContext filterContext)
        {
            var session = filterContext.HttpContext.Session;
            var vaiTro = session?["VaiTro"] as string;

            if (session?["MaNguoiDung"] == null)
            {
                // Chưa đăng nhập - trả về đúng trang đăng nhập, không phải "không đủ quyền"
                filterContext.Result = new RedirectToRouteResult(
                    new System.Web.Routing.RouteValueDictionary
                    {
                        { "controller", "Account" },
                        { "action", "Login" }
                    });
                return;
            }

            if (vaiTro == null || !_vaiTroChoPhep.Contains(vaiTro))
            {
                filterContext.Controller.TempData["ErrorMessage"] =
                    "Bạn không có quyền truy cập chức năng này.";
                filterContext.Result = new RedirectToRouteResult(
                    new System.Web.Routing.RouteValueDictionary
                    {
                        { "controller", "Home" },
                        { "action", "Index" }
                    });
                return;
            }

            base.OnActionExecuting(filterContext);
        }
    }
}