using System.Web.Mvc;

namespace QLK.Controllers
{
    [Authorize] // Bắt buộc phải đăng nhập mới được vào trang này
    public class HomeController : Controller
    {
        public ActionResult Index()
        {
            // Lấy thông tin user từ Session để hiển thị ra màn hình
            ViewBag.HoTen = Session["HoTen"]?.ToString() ?? User.Identity.Name;
            ViewBag.VaiTro = Session["VaiTro"]?.ToString() ?? "N/A";

            return View();
        }
    }
}