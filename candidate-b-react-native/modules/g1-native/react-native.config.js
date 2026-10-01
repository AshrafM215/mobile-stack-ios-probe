// Candidate B adapter (TurboModule NativeG1) - NON-PRODUCTION / SYNTHETIC DATA ONLY.
module.exports = {
  dependency: {
    platforms: {
      android: {
        sourceDir: './android',
        packageImportPath: 'import com.example.g1bench.g1native.G1NativePackage;',
        packageInstance: 'new G1NativePackage()',
      },
      ios: {},
    },
  },
};
