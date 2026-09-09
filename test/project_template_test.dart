import 'package:flutter_boilerplate/src/base/qa/project_template.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ProjectTemplate.custom', () {
    test('preserves repoRelPaths — regression: these used to be silently dropped',
        () {
      final project = ProjectTemplate.custom(
        name: 'Cent',
        projectsRoot: '/Users/keshavgupta/Downloads/Projects',
        repoRelPaths: {
          'app': 'crichq-app-flutter',
          'web': 'crichq-webapp-nextjs',
          'mobile_tests': 'centurion-app-automation-tests-ts',
        },
        repoBranches: {'app': 'main'},
      );

      expect(project.repos, hasLength(3));
      expect(project.repos['app']?.relPath, 'crichq-app-flutter');
      expect(project.repos['app']?.branch, 'main');
      expect(project.repos['web']?.relPath, 'crichq-webapp-nextjs');
      expect(project.repos['web']?.branch, 'develop'); // default, unspecified
      expect(project.repos['mobile_tests']?.relPath,
          'centurion-app-automation-tests-ts');
    });

    test('no repoRelPaths given — repos is empty, not a crash', () {
      final project = ProjectTemplate.custom(
        name: 'Blank',
        projectsRoot: '/tmp',
      );
      expect(project.repos, isEmpty);
    });

    test('an arbitrary user-typed role name (not app/web/mobile_tests) works too',
        () {
      final project = ProjectTemplate.custom(
        name: 'Custom roles',
        projectsRoot: '/tmp',
        repoRelPaths: {'backend': 'my-backend-repo'},
      );
      expect(project.repos['backend']?.relPath, 'my-backend-repo');
    });
  });
}
