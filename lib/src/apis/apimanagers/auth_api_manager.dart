import '../../base/dependencyinjection/locator.dart';

import '../api_route_constant.dart';
import '../api_service.dart';
import '../../models/res_base_model.dart';

class AuthApiManager {
  Future<ResBaseModel> login(ResBaseModel request) async {
    final response = await locator<ApiService>().post(
      apiLogin,
      data: request.toJson(),
    );
    return ResBaseModel.fromJson(response?.data);
  }
}
