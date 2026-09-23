/* MaSi: Thor-only FastRPC PD-type context banks (stock SH5001 ADSP).
 * Appended to qcs8550-ayn-thor.dts. Matches Batocera suckbluefrog gyro DT.
 */

&remoteproc_adsp {
	glink-edge {
		fastrpc {
			compute-cb@3 {
				qcom,pd-type = <1>;
			};

			compute-cb@4 {
				qcom,pd-type = <2>;
			};

			compute-cb@5 {
				qcom,nsessions = <8>;
				qcom,pd-type = <3>;
			};

			compute-cb@6 {
				qcom,pd-type = <7>;
			};

			compute-cb@7 {
				qcom,pd-type = <7>;
			};
		};
	};
};
