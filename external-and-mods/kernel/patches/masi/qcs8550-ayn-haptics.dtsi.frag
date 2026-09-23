&pmk8550 {
	pmk8550_sdam_9d00: nvram@9d00 {
		compatible = "qcom,spmi-sdam";
		reg = <0x9d00>;
	};
};

&pm8550b {
	pm8550b_hv_haptics: qcom,hv-haptics@f000 {
		compatible = "qcom,hv-haptics";
		reg = <0xf000>, <0xf100>, <0xf200>;
		interrupts = <0x07 0xf0 0x1 IRQ_TYPE_EDGE_RISING>;
		interrupt-names = "fifo-empty";
		qcom,vmax-mv = <5000>;
		qcom,brake-mode = <BRAKE_CLOSE_LOOP>;
		qcom,brake-pattern = /bits/ 8 <0xff 0x3f 0x1f>;
		qcom,lra-period-us = <5880>;
		qcom,drv-sig-shape = <WF_SINE>;
		qcom,brake-sig-shape = <WF_SINE>;
		nvmem-names = "hap_cfg_sdam";
		nvmem = <&pmk8550_sdam_9d00>;
		status = "ok";

		hap_swr_slave_reg: qcom,hap-swr-slave-reg {
			regulator-name = "hap-swr-slave-reg";
		};

		effect_0 {
			qcom,effect-id = <0x00>;
			/* qcom,wf-auto-res-disable; */
			qcom,wf-brake-pattern = /bits/ 8 <0x0 0x0 0x0>;
			qcom,wf-pattern-data =  <0x15f 0x00 0x00>,
						<0x17f 0x00 0x00>,
						<0x19f 0x00 0x00>,
						<0x1df 0x00 0x00>,
						<0x1df 0x00 0x00>,
						<0x19f 0x00 0x00>,
						<0x17f 0x00 0x00>,
						<0x15f 0x00 0x00>;
			qcom,wf-pattern-period-us = <5880>;
			qcom,wf-vmax-mv = <5000>;
		};

		effect_1 {
			qcom,effect-id = <0x01>;
			/* qcom,wf-auto-res-disable; */
			qcom,wf-brake-pattern = /bits/ 8 <0x0 0x0 0x0>;
			qcom,wf-pattern-data =  <0x01f 0x00 0x00>,
						<0x03f 0x00 0x00>,
						<0x05f 0x00 0x00>,
						<0x07f 0x00 0x00>,
						<0x17f 0x00 0x00>,
						<0x15f 0x00 0x00>,
						<0x13f 0x00 0x00>,
						<0x11f 0x00 0x00>;
			qcom,wf-pattern-period-us = <5880>;
			qcom,wf-vmax-mv = <3200>;
		};

		effect_2 {
			qcom,effect-id = <0x02>;
			/* qcom,wf-auto-res-disable; */
			qcom,wf-brake-pattern = /bits/ 8 <0x0 0x0 0x0>;
			qcom,wf-pattern-data =  <0x01f 0x00 0x00>,
						<0x03f 0x00 0x00>,
						<0x05f 0x00 0x00>,
						<0x07f 0x00 0x00>,
						<0x17f 0x00 0x00>,
						<0x15f 0x00 0x00>,
						<0x13f 0x00 0x00>,
						<0x11f 0x00 0x00>;
			qcom,wf-pattern-period-us = <5880>;
			qcom,wf-vmax-mv = <3200>;
		};

		effect_3 {
			qcom,effect-id = <0x03>;
			/* qcom,wf-auto-res-disable; */
			qcom,wf-brake-pattern = /bits/ 8 <0x0 0x0 0x0>;
			qcom,wf-pattern-data =  <0x01f 0x00 0x00>,
						<0x03f 0x00 0x00>,
						<0x05f 0x00 0x00>,
						<0x07f 0x00 0x00>,
						<0x17f 0x00 0x00>,
						<0x15f 0x00 0x00>,
						<0x13f 0x00 0x00>,
						<0x11f 0x00 0x00>;
			qcom,wf-pattern-period-us = <5880>;
			qcom,wf-vmax-mv = <3200>;
		};

		effect_4 {
			qcom,effect-id = <0x04>;
			/* qcom,wf-auto-res-disable; */
			qcom,wf-brake-pattern = /bits/ 8 <0x0 0x0 0x0>;
			qcom,wf-pattern-data =  <0x01f 0x00 0x00>,
						<0x03f 0x00 0x00>,
						<0x05f 0x00 0x00>,
						<0x07f 0x00 0x00>,
						<0x17f 0x00 0x00>,
						<0x15f 0x00 0x00>,
						<0x13f 0x00 0x00>,
						<0x11f 0x00 0x00>;
			qcom,wf-pattern-period-us = <5880>;
			qcom,wf-vmax-mv = <3200>;
		};

		effect_5 {
			qcom,effect-id = <0x05>;
			/* qcom,wf-auto-res-disable; */
			qcom,wf-brake-pattern = /bits/ 8 <0x0 0x0 0x0>;
			qcom,wf-pattern-data =  <0x11f 0x00 0x00>,
						<0x13f 0x00 0x00>,
						<0x15f 0x00 0x00>,
						<0x17f 0x00 0x00>,
						<0x17f 0x00 0x00>,
						<0x15f 0x00 0x00>,
						<0x13f 0x00 0x00>,
						<0x11f 0x00 0x00>;
			qcom,wf-pattern-period-us = <5880>;
			qcom,wf-vmax-mv = <5000>;
		};

		primitive_0 {
			qcom,primitive-id = <0x00>;
			qcom,wf-auto-res-disable;
			qcom,wf-brake-pattern = /bits/ 8 <0x0 0x0 0x0>;
			qcom,wf-pattern-data = <0x00 0x00 0x00 0x00 0x00 0x00>;
			qcom,wf-pattern-period-us = <5880>;
			qcom,wf-vmax-mv = <2400>;
		};

		primitive_1 {
			qcom,primitive-id = <0x01>;
			qcom,wf-auto-res-disable;
			qcom,wf-brake-pattern = /bits/ 8 <0x0 0x0 0x0>;
			qcom,wf-pattern-data = <0xff 0x00 0x00 0x7f 0x00 0x00>;
			qcom,wf-pattern-period-us = <5880>;
			qcom,wf-vmax-mv = <2400>;
		};

		primitive_2 {
			qcom,primitive-id = <0x02>;
			qcom,wf-auto-res-disable;
			qcom,wf-brake-pattern = /bits/ 8 <0x0 0x0 0x0>;
			qcom,wf-pattern-data = <0xff 0x00 0x00 0x7f 0x00 0x00>;
			qcom,wf-pattern-period-us = <5880>;
			qcom,wf-vmax-mv = <2400>;
		};

		primitive_3 {
			qcom,primitive-id = <0x03>;
			qcom,wf-auto-res-disable;
			qcom,wf-brake-pattern = /bits/ 8 <0x0 0x0 0x0>;
			qcom,wf-pattern-data = <0xff 0x00 0x00 0x7f 0x00 0x00>;
			qcom,wf-pattern-period-us = <5880>;
			qcom,wf-vmax-mv = <2400>;
		};

		primitive_4 {
			qcom,primitive-id = <0x04>;
			qcom,wf-auto-res-disable;
			qcom,wf-brake-pattern = /bits/ 8 <0x0 0x0 0x0>;
			qcom,wf-pattern-data = <0xff 0x00 0x00 0x7f 0x00 0x00>;
			qcom,wf-pattern-period-us = <5880>;
			qcom,wf-vmax-mv = <2400>;
		};

		primitive_5 {
			qcom,primitive-id = <0x05>;
			qcom,wf-auto-res-disable;
			qcom,wf-brake-pattern = /bits/ 8 <0x0 0x0 0x0>;
			qcom,wf-pattern-data = <0xff 0x00 0x00 0x7f 0x00 0x00>;
			qcom,wf-pattern-period-us = <5880>;
			qcom,wf-vmax-mv = <2400>;
		};

		primitive_6 {
			qcom,primitive-id = <0x06>;
			qcom,wf-auto-res-disable;
			qcom,wf-brake-pattern = /bits/ 8 <0x0 0x0 0x0>;
			qcom,wf-pattern-data = <0xff 0x00 0x00 0x7f 0x00 0x00>;
			qcom,wf-pattern-period-us = <5880>;
			qcom,wf-vmax-mv = <2400>;
		};

		primitive_7 {
			qcom,primitive-id = <0x07>;
			qcom,wf-auto-res-disable;
			qcom,wf-brake-pattern = /bits/ 8 <0x0 0x0 0x0>;
			qcom,wf-pattern-data = <0xff 0x00 0x00 0x7f 0x00 0x00>;
			qcom,wf-pattern-period-us = <5880>;
			qcom,wf-vmax-mv = <2400>;
		};

		primitive_8 {
			qcom,primitive-id = <0x08>;
			qcom,wf-auto-res-disable;
			qcom,wf-brake-pattern = /bits/ 8 <0x0 0x0 0x0>;
			qcom,wf-pattern-data = <0xff 0x00 0x00 0x7f 0x00 0x00>;
			qcom,wf-pattern-period-us = <5880>;
			qcom,wf-vmax-mv = <2400>;
		};
	};
};

