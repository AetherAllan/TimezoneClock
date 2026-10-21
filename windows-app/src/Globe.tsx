import { Canvas, useFrame } from "@react-three/fiber";
import { useRef } from "react";
import type { Group } from "three";

function Planet() {
  const globe = useRef<Group>(null);
  useFrame((_, delta) => {
    if (globe.current) globe.current.rotation.y += Math.min(delta, 0.05) * 0.13;
  });
  return (
    <group ref={globe} rotation={[0.2, -0.35, 0]}>
      <mesh>
        <sphereGeometry args={[1, 48, 32]} />
        <meshStandardMaterial color="#123b54" roughness={0.8} metalness={0.18} />
      </mesh>
      <mesh scale={1.007}>
        <sphereGeometry args={[1, 24, 16]} />
        <meshBasicMaterial color="#65e8dc" wireframe transparent opacity={0.33} />
      </mesh>
      <mesh rotation={[0.4, 0.2, 0]}>
        <torusGeometry args={[1.27, 0.008, 8, 96]} />
        <meshBasicMaterial color="#7ca7ff" transparent opacity={0.6} />
      </mesh>
    </group>
  );
}

export default function Globe() {
  return (
    <div className="globe-preview" aria-hidden="true">
      <Canvas camera={{ position: [0, 0, 3.4], fov: 38 }} dpr={[1, 1.5]} gl={{ alpha: true, antialias: true }}>
        <ambientLight intensity={1.15} />
        <directionalLight position={[2, 1, 3]} intensity={1.65} color="#b5f5ef" />
        <Planet />
      </Canvas>
    </div>
  );
}
